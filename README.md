# zlib-fuzz

libFuzzer fuzz target for zlib(-ng), which focuses not on a single function
call, but rather on sequences thereof. It can work both stand-alone and with
libprotobuf-mutator.

# Example: fuzzing zlib-ng with libFuzzer

```
$ git submodule update --init --recursive
$ make all -j"$(nproc)"
$ build/fuzz
```
# Example: fuzzing zlib-ng with AFL

```
$ git submodule update --init --recursive
$ make afl -j"$(nproc)"
```
# Example: fuzzing zlib-ng with AFL + symcc (Requires tmux)

```
$ git submodule update --init --recursive
$ make symcc -j"$(nproc)"
```