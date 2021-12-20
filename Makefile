# Optional environment variables:
# - WORKDIR: path to compile directory
# - ZLIB: path to a zlib build directory configured with libFuzzer
# - ZLIB_AFL: path to a (different) zlib build directory configured with AFL
# - ZLIB_SYMCC: path to a (yet another) zlib build directory configured with SymCC
# - OUTPUT_AFL: path to afl fuzzing directory
# Required programs in $PATH:
# - clang / clang++
# - afl-fuzz / afl-clang-lto / afl-clang-lto++

WORKDIR?=
ifeq ($(WORKDIR),)
	OUTPUT=build/
else
	OUTPUT=$(WORKDIR)/
endif
TMP=$(shell mkdir -p $(OUTPUT) && cd $(OUTPUT) && pwd)
RPATH=$(realpath $(TMP))/

CC=clang
CXX=clang++
AFLCC=afl-clang-lto
AFLCXX=afl-clang-lto++
AFL_FUZZ=afl-fuzz
OUTPUT_AFL?=$(OUTPUT)afl_out
PROTOBUF_PATH=$(OUTPUT)libprotobuf-mutator/build/external.protobuf
PROTOC=$(PROTOBUF_PATH)/bin/protoc
C_CXX_FLAGS=-fPIC -Wall -Wextra -Werror -O2 -g
override CFLAGS:=$(C_CXX_FLAGS) -std=c11 $(CFLAGS)
override CXXFLAGS:=$(C_CXX_FLAGS) -std=c++17 -isystem libprotobuf-mutator -isystem $(PROTOBUF_PATH)/include $(CXXFLAGS)
override LDFLAGS:=-L$(OUTPUT)libprotobuf-mutator/build/src -fPIC -L$(OUTPUT)libprotobuf-mutator/build/src/libfuzzer -L$(PROTOBUF_PATH)/lib $(LDFLAGS)
ZLIB?=$(OUTPUT)zlib-ng/build-libfuzzer
ZLIB_AFL?=$(OUTPUT)zlib-ng/build-afl
ZLIB_SYMCC?=$(OUTPUT)zlib-ng/build-symcc
LIBZ_A:=$(ZLIB)/libz.a
LIBZ_A_AFL:=$(ZLIB_AFL)/libz.a
LIBZ_A_SYMCC:=$(ZLIB_SYMCC)/libz.a
override ZLIB_NG_CMFLAGS:=-DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_SHARED_LIBS=0 -DZLIB_COMPAT=ON $(ZLIB_NG_CMFLAGS)
SYMCC=$(RPATH)symcc/build/symcc

.PHONY: all
all: $(OUTPUT)fuzz $(OUTPUT)fuzz_libprotobuf_mutator $(OUTPUT)fuzz_afl $(OUTPUT)fuzz_symcc

$(OUTPUT)fuzz_libprotobuf_mutator: $(OUTPUT)fuzz_target_libprotobuf_mutator.o $(OUTPUT)fuzz_target.pb.o $(LIBZ_A)
	$(CXX) $(LDFLAGS) -fsanitize=address,fuzzer $(OUTPUT)fuzz_target_libprotobuf_mutator.o $(OUTPUT)fuzz_target.pb.o -o $@ $(LIBZ_A) -lprotobuf-mutator-libfuzzer -lprotobuf-mutator -lprotobuf

.PHONY: libfuzzer
libfuzzer: $(OUTPUT)fuzz
	mkdir $(OUTPUT)fuzz_out && $(OUTPUT)fuzz $(OUTPUT)fuzz_out seed -print_final_stats=1

$(OUTPUT)fuzz: $(OUTPUT)fuzz_target.o $(LIBZ_A)
	$(CXX) $(LDFLAGS) -fsanitize=address,fuzzer $(OUTPUT)fuzz_target.o -o $@ $(LIBZ_A)

.PHONY: afl
afl: $(OUTPUT)fuzz_afl
	$(AFL_FUZZ) -i seed -o $(OUTPUT_AFL) -- $(OUTPUT)fuzz_afl

FUZZ_AFL_OBJS=$(OUTPUT)fuzz_target_afl.o $(OUTPUT)afl_driver.o $(LIBZ_A_AFL)

$(OUTPUT)fuzz_afl: $(FUZZ_AFL_OBJS)
	AFL_USE_ASAN=1 $(AFLCXX) $(LDFLAGS) -o $@ $(FUZZ_AFL_OBJS)

$(OUTPUT)fuzz_target.o: fuzz_target.cpp | fmt
	$(CC) $(CFLAGS) -x c -fsanitize=address,fuzzer -DZLIB_CONST -I$(OUTPUT) -c fuzz_target.cpp -o $@

$(OUTPUT)fuzz_target_libprotobuf_mutator.o: fuzz_target.cpp $(OUTPUT)fuzz_target.pb.h | fmt
	$(CXX) $(CXXFLAGS) -fsanitize=address,fuzzer -DUSE_LIBPROTOBUF_MUTATOR -DZLIB_CONST -I$(OUTPUT) -c fuzz_target.cpp -o $@

$(OUTPUT)fuzz_target_afl.o: fuzz_target.cpp | fmt
	AFL_USE_ASAN=1 $(AFLCC) $(CFLAGS) -x c -DZLIB_CONST -I$(OUTPUT) -c fuzz_target.cpp -o $@

$(OUTPUT)fuzz_target_symcc.o: fuzz_target.cpp $(SYMCC) | fmt
	$(SYMCC) $(CFLAGS) -x c -DZLIB_CONST -I$(OUTPUT) -c fuzz_target.cpp -o $@

$(OUTPUT)symcc_driver.o: symcc_driver.c $(SYMCC) | fmt
	$(SYMCC) $(CFLAGS) -c $^ -o $@

FUZZ_SYMCC_OBJS=$(OUTPUT)fuzz_target_symcc.o $(OUTPUT)symcc_driver.o $(LIBZ_A_SYMCC)

$(OUTPUT)fuzz_symcc: $(FUZZ_SYMCC_OBJS) $(SYMCC)
	$(SYMCC) $(LDFLAGS) -o $@ $(FUZZ_SYMCC_OBJS)

$(OUTPUT)fuzz_target.pb.o: $(OUTPUT)fuzz_target.pb.cc $(OUTPUT)fuzz_target.pb.h
	$(CXX) $(CXXFLAGS) -c $(OUTPUT)fuzz_target.pb.cc -o $@

$(OUTPUT)fuzz_target.pb.cc $(OUTPUT)fuzz_target.pb.h: fuzz_target.proto $(PROTOC)
	$(PROTOC) --cpp_out=$(OUTPUT) fuzz_target.proto

$(OUTPUT)afl_driver.o: afl_driver.cpp
	$(CXX) $(CXXFLAGS) -c $^ -o $@

$(OUTPUT)libprotobuf-mutator/build/Makefile: libprotobuf-mutator/CMakeLists.txt
	mkdir -p $(OUTPUT)libprotobuf-mutator/build && \
		cmake \
			-S libprotobuf-mutator \
			-B $(OUTPUT)libprotobuf-mutator/build \
			-DCMAKE_C_COMPILER=$(CC) \
			-DCMAKE_CXX_COMPILER=$(CXX) \
			-DCMAKE_BUILD_TYPE=RelWithDebInfo \
			-DLIB_PROTO_MUTATOR_DOWNLOAD_PROTOBUF=ON

$(PROTOC): $(OUTPUT)libprotobuf-mutator/build/Makefile
	cd $(OUTPUT)libprotobuf-mutator/build && $(MAKE)

$(ZLIB)/Makefile: zlib-ng/CMakeLists.txt
	mkdir -p $(ZLIB) && \
		cmake \
			-S zlib-ng \
			-B $(ZLIB) \
			-DCMAKE_C_COMPILER=$(CC) \
			-DCMAKE_C_FLAGS=-fsanitize=address,fuzzer-no-link \
			$(ZLIB_NG_CMFLAGS)

$(LIBZ_A): $(ZLIB)/Makefile
	cd $(ZLIB) && $(MAKE)

$(ZLIB_AFL)/Makefile: zlib-ng/CMakeLists.txt
	mkdir -p $(ZLIB_AFL) && \
		AFL_USE_ASAN=1 cmake \
			-S zlib-ng \
			-B $(ZLIB_AFL) \
			-DCMAKE_C_COMPILER=$(AFLCC) \
			$(ZLIB_NG_CMFLAGS)

$(LIBZ_A_AFL): $(ZLIB_AFL)/Makefile
	cd $(ZLIB_AFL) && AFL_USE_ASAN=1 $(MAKE)

$(OUTPUT)symcc/build/Makefile: symcc/CMakeLists.txt
	mkdir -p $(OUTPUT)symcc/build && \
		cmake -S symcc \
		-B $(OUTPUT)symcc/build \
		-DQSYM_BACKEND=ON \
		-DZ3_TRUST_SYSTEM_VERSION=ON \
		$(SYMCC_CMFLAGS)

$(SYMCC): $(OUTPUT)symcc/build/Makefile
	cd $(OUTPUT)symcc/build && $(MAKE)

$(ZLIB_SYMCC)/Makefile: \
		zlib-ng/CMakeLists.txt \
		$(SYMCC)
	mkdir -p $(ZLIB_SYMCC) && \
		cmake \
			-S zlib-ng \
			-B $(ZLIB_SYMCC) \
			-DCMAKE_C_COMPILER=$(SYMCC) \
			-DWITH_SSE2=OFF \
			-DWITH_CRC32_VX=OFF \
			$(ZLIB_NG_CMFLAGS)

$(LIBZ_A_SYMCC): $(ZLIB_SYMCC)/Makefile
	cd $(ZLIB_SYMCC) && $(MAKE)

$(OUTPUT)symcc/build/bin/symcc_fuzzing_helper:
	cargo install --root $(OUTPUT)symcc/build --path symcc/util/symcc_fuzzing_helper

.PHONY: symcc
symcc: $(OUTPUT)fuzz_symcc $(OUTPUT)fuzz_afl $(OUTPUT)symcc/build/bin/symcc_fuzzing_helper
	rm -rf $(OUTPUT_AFL)/master $(OUTPUT_AFL)/slave1 $(OUTPUT_AFL)/symcc_1
	tmux \
		new-session "$(AFL_FUZZ) -M master -i seed -o $(OUTPUT_AFL) -m none -- $(OUTPUT)fuzz_afl" \; \
		new-window "$(AFL_FUZZ) -S slave1 -i seed -o $(OUTPUT_AFL) -m none -- $(OUTPUT)fuzz_afl" \; \
		new-window "(OUTPUT)symcc/build/bin/symcc_fuzzing_helper -o $(OUTPUT_AFL) -a slave1 -n symcc_1 -v -- $(OUTPUT)fuzz_symcc"

.PHONY: fmt
fmt:
	clang-format -i -style=llvm fuzz_target.cpp symcc_driver.c

.PHONY: clean
clean:
	rm -rf $(ZLIB)
	rm -rf $(ZLIB_AFL)
	rm -rf $(ZLIB_SYMCC)
	rm -f $(OUTPUT)*.o
	rm -f $(OUTPUT)*.a
	rm -f $(OUTPUT)fuzz $(OUTPUT)fuzz_libprotobuf_mutator $(OUTPUT)fuzz_afl $(OUTPUT)fuzz_symcc

.PHONY: distclean
distclean: clean
	rm -rf $(OUTPUT_AFL)
	rm -rf $(OUTPUT)