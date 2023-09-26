# FFDef

Small tool for automatically generating C code for reading and writing simple
file formats.

This tool revolves around definition files, where each defines a unique file
format or a unique file format version. Each file format has a human-friendly
name and a namespace used in the generated C code.

For examples of these definition files, check the [examples directory](examples).

## Build

```sh
zig build
```

## Test

```sh
zig build test
```
