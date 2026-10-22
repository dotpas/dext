# DextASTParser

Console application that parses Delphi source files using [DelphiAST](https://github.com/RomanYankovsky/DelphiAST) (Stefan Glienke's fork) and generates XML output.

## Purpose

Generate Abstract Syntax Tree (AST) XML files for all Dext Framework units. This is the first step toward creating automated API documentation that supports modern Delphi generics.

## Requirements

- Delphi 12 (or compatible version)
- DelphiAST (Glienke fork or upstream) on the project **Unit search path** — clone/configure locally; do not hardcode a machine path in the repo

## Usage

1. Point `DextASTParser.dproj` Unit search path at your DelphiAST `Source` (+ `SimpleParser`) folders.
2. Build the project (`Ctrl+F9`)
3. Run from the command line (paths relative to your checkout of **this** repository):

```cmd
DextASTParser.exe <input_dir> <output_dir> [-i include_path1;include_path2]
```

### Example

From the repo root (adjust if your output layout differs):

```cmd
DextASTParser.exe Sources Docs\API\xml -i Sources\Core
```

## Output

- XML files are generated in the `<output_dir>` preserving the input directory structure.
- Each `.pas` file produces a corresponding `.xml` file with the AST.

## Example Output

```xml
<?xml version="1.0"?>
<UNIT line="1" col="1" name="Dext.Core.SmartTypes">
  <INTERFACE begin_line="3" begin_col="1" end_line="100" end_col="1">
```

## Notes

Configure DelphiAST via IDE / dproj search path on your machine. Keep those paths out of committed docs.
