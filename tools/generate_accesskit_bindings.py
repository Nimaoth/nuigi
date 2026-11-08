#!/usr/bin/env python3
"""Generates Nim bindings for the AccessKit C API.

Parses vendor/accesskit-c/include/accesskit.h with libclang once per
supported platform (Windows, macOS, Linux/BSD), merges the declarations into
a simple intermediate model (dumped to build/accesskit_api.json for
inspection), and writes src/nuigi/backend/accesskit/accesskit.nim with
platform `when` guards.

System headers are replaced by the stubs in tools/accesskit_stubs so the
header can be parsed for every platform on any host.

Requirements:
  - libclang shared library (found next to `clang` on PATH, or set
    LIBCLANG_PATH to the full path of libclang.dll/.so/.dylib)
  - pip install clang  (version matching the installed libclang)

Usage:
  python tools/generate_accesskit_bindings.py
"""

import json
import os
import re
import shutil
import subprocess
import sys

from clang import cindex
from clang.cindex import CursorKind, TypeKind

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEADER = os.path.join(ROOT, "vendor", "accesskit-c", "include", "accesskit.h")
STUBS = os.path.join(ROOT, "tools", "accesskit_stubs")
OUT_NIM = os.path.join(ROOT, "src", "nuigi", "backend", "accesskit",
                       "accesskit.nim")
OUT_JSON = os.path.join(ROOT, "build", "accesskit_api.json")

PLATFORMS = [
    ("windows", ["-target", "x86_64-pc-windows-msvc"]),
    ("macosx", ["-target", "x86_64-apple-darwin"]),
    ("linux", ["-target", "x86_64-unknown-linux-gnu"]),
]

COMMON_ARGS = ["-x", "c", "-std=c11", "-nostdlibinc", "-isystem", STUBS]


def resource_dir_args():
    # libclang does not always locate clang's builtin headers (stdarg.h,
    # stdint.h, ...); ask the clang driver for its resource directory.
    clang_exe = shutil.which("clang")
    if not clang_exe:
        return []
    out = subprocess.run([clang_exe, "-print-resource-dir"],
                         capture_output=True, text=True, check=True)
    return ["-resource-dir", out.stdout.strip()]

# Nim `when` conditions per platform set. The Linux parse covers the whole
# Unix guard group in the header ( __linux__ / BSDs ).
GUARDS = {
    frozenset(["windows"]): "defined(windows)",
    frozenset(["macosx"]): "defined(macosx)",
    frozenset(["linux"]): "defined(linux) or defined(freebsd) or "
                          "defined(netbsd) or defined(openbsd) or "
                          "defined(dragonfly)",
    frozenset(["windows", "macosx"]): "defined(windows) or defined(macosx)",
    frozenset(["windows", "linux"]): "defined(windows) or defined(linux)",
    frozenset(["macosx", "linux"]): "defined(macosx) or defined(linux)",
}

ALL_PLATFORMS = frozenset(p for p, _ in PLATFORMS)

# Typedefs from system headers (and the windows.h stub) mapped by name.
SPECIAL_TYPEDEFS = {
    "int8_t": "int8", "int16_t": "int16", "int32_t": "int32",
    "int64_t": "int64",
    "uint8_t": "uint8", "uint16_t": "uint16", "uint32_t": "uint32",
    "uint64_t": "uint64",
    "size_t": "csize_t", "intptr_t": "int", "uintptr_t": "uint",
    "ptrdiff_t": "int",
    # LONG_PTR/UINT_PTR-sized Windows types; Nim's int/uint match the
    # pointer size on both 32- and 64-bit targets.
    "HWND": "pointer", "LRESULT": "int", "WPARAM": "uint", "LPARAM": "int",
}

BUILTIN_TYPES = {
    TypeKind.BOOL: "bool",
    TypeKind.DOUBLE: "float64",
    TypeKind.FLOAT: "float32",
    TypeKind.INT: "cint",
    TypeKind.UINT: "cuint",
    TypeKind.SHORT: "cshort",
    TypeKind.USHORT: "cushort",
    TypeKind.LONG: "clong",
    TypeKind.ULONG: "culong",
    TypeKind.LONGLONG: "clonglong",
    TypeKind.ULONGLONG: "culonglong",
    TypeKind.CHAR_S: "char",
    TypeKind.CHAR_U: "char",
    TypeKind.SCHAR: "int8",
    TypeKind.UCHAR: "uint8",
}

NIM_KEYWORDS = {
    "addr", "and", "as", "asm", "bind", "block", "break", "case", "cast",
    "concept", "const", "continue", "converter", "defer", "discard",
    "distinct", "div", "do", "elif", "else", "end", "enum", "except",
    "export", "finally", "for", "from", "func", "if", "import", "in",
    "include", "interface", "is", "isnot", "iterator", "let", "macro",
    "method", "mixin", "mod", "nil", "not", "notin", "object", "of", "or",
    "out", "proc", "ptr", "raise", "ref", "return", "shl", "shr", "static",
    "template", "try", "tuple", "type", "using", "var", "when", "while",
    "xor", "yield",
}


def type_name(c_name):
    # accesskit_tree_update -> AccessKitTreeUpdate
    assert c_name.startswith("accesskit_"), c_name
    parts = c_name[len("accesskit_"):].split("_")
    return "AccessKit" + "".join(p[:1].upper() + p[1:] for p in parts if p)


def proc_name(c_name):
    # accesskit_node_set_role -> nodeSetRole
    assert c_name.startswith("accesskit_"), c_name
    parts = c_name[len("accesskit_"):].split("_")
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:] if p)


def const_name(c_name):
    # ACCESSKIT_ROLE_WINDOW -> ROLE_WINDOW
    assert c_name.startswith("ACCESSKIT_"), c_name
    return c_name[len("ACCESSKIT_"):]


def ident(name, index):
    # Field/parameter name as a valid Nim identifier.
    if not name:
        return "a%d" % index
    name = "".join(p[:1].upper() + p[1:] if i else p
                   for i, p in enumerate(name.split("_")) if p)
    if not name or name[0].isdigit():
        name = "field" + name
    if name.lower() in NIM_KEYWORDS:
        name += "Arg"
    return name


class Parser:
    def __init__(self):
        self.model = {}       # name -> decl dict
        self.order = []       # declaration order of names
        self.platform = None

    def map_type(self, t):
        kind = t.kind
        if kind == TypeKind.ELABORATED:
            return self.map_type(t.get_named_type())
        if kind == TypeKind.TYPEDEF:
            name = t.spelling.replace("const ", "")
            if name in SPECIAL_TYPEDEFS:
                return SPECIAL_TYPEDEFS[name]
            if name.startswith("accesskit_"):
                return type_name(name)
            return self.map_type(
                t.get_declaration().underlying_typedef_type)
        if kind == TypeKind.POINTER:
            pointee = t.get_pointee()
            canonical = pointee.get_canonical()
            if canonical.kind in (TypeKind.CHAR_S, TypeKind.CHAR_U):
                return "cstring"
            if canonical.kind == TypeKind.VOID:
                return "pointer"
            return "ptr " + self.map_type(pointee)
        if kind == TypeKind.RECORD:
            return type_name(t.spelling.replace("struct ", "")
                             .replace("union ", ""))
        if kind == TypeKind.ENUM:
            return type_name(t.spelling.replace("enum ", ""))
        if kind == TypeKind.CONSTANTARRAY:
            return "array[%d, %s]" % (t.element_count,
                                      self.map_type(t.element_type))
        if kind in BUILTIN_TYPES:
            return BUILTIN_TYPES[kind]
        raise RuntimeError("unhandled type %s (%s)" % (t.spelling, kind))

    def map_result(self, t):
        if t.get_canonical().kind == TypeKind.VOID:
            return None
        return self.map_type(t)

    def params(self, cursor):
        result = []
        for i, arg in enumerate(cursor.get_arguments()):
            result.append({"name": ident(arg.spelling, i),
                           "type": self.map_type(arg.type)})
        return result

    def callback_params(self, cursor, proto):
        # Typedef cursors don't expose get_arguments(); take the types from
        # the function prototype and the names from the PARM_DECL children.
        names = [c.spelling for c in cursor.get_children()
                 if c.kind == CursorKind.PARM_DECL]
        result = []
        for i, arg_type in enumerate(proto.argument_types()):
            name = names[i] if i < len(names) else ""
            result.append({"name": ident(name, i),
                           "type": self.map_type(arg_type)})
        return result

    def add(self, name, decl, ignore=()):
        existing = self.model.get(name)
        if existing is None:
            decl["platforms"] = [self.platform]
            decl["name"] = name
            self.model[name] = decl
            self.order.append(name)
        else:
            if self.platform not in existing["platforms"]:
                existing["platforms"].append(self.platform)
            skip = ("platforms", "name") + tuple(ignore)
            check = {k: v for k, v in existing.items() if k not in skip}
            new = {k: v for k, v in decl.items() if k not in skip}
            if check != new:
                raise RuntimeError(
                    "declaration of %s differs between platforms" % name)

    def struct_fields(self, cursor, nim_name, aux):
        # Returns the field list; anonymous unions/structs become auxiliary
        # named types collected in `aux`.
        fields = []
        anon = 0
        for child in cursor.get_children():
            if child.kind == CursorKind.FIELD_DECL:
                decl = child.type.get_declaration()
                if decl.kind != CursorKind.NO_DECL_FOUND and \
                        decl.is_anonymous():
                    raise RuntimeError(
                        "anonymous field type with a name in %s" % nim_name)
                fields.append({"name": ident(child.spelling, len(fields)),
                               "type": self.map_type(child.type)})
            elif child.kind in (CursorKind.UNION_DECL,
                                CursorKind.STRUCT_DECL):
                # C11 anonymous member: synthesize a named Nim type for it.
                inner_name = nim_name + "Anon%d" % anon
                anon += 1
                inner_fields = self.struct_fields(child, inner_name, aux)
                aux.append({"kind": "struct", "nim_name": inner_name,
                            "cname": None,
                            "union": child.kind == CursorKind.UNION_DECL,
                            "fields": inner_fields, "brief": None})
                fields.append({"name": "anon%d" % (anon - 1),
                               "type": inner_name})
        # Flatten single-field anonymous wrappers (the structs inside the
        # action data union): a struct with exactly one field has the same
        # layout as the field itself.
        flattened = []
        for field in fields:
            inner = next((a for a in aux if a["nim_name"] == field["type"]
                          and not a["union"]), None)
            if inner is not None and len(inner["fields"]) == 1:
                aux.remove(inner)
                flattened.append(inner["fields"][0])
            else:
                flattened.append(field)
        return flattened

    def visit(self, cursor):
        name = cursor.spelling
        kind = cursor.kind
        brief = cursor.brief_comment or None
        if kind == CursorKind.ENUM_DECL and name.startswith("accesskit_"):
            constants = [{"name": const_name(c.spelling),
                          "cname": c.spelling,
                          "value": c.enum_value}
                         for c in cursor.get_children()
                         if c.kind == CursorKind.ENUM_CONSTANT_DECL]
            self.add(name, {"kind": "enum", "nim_name": type_name(name),
                            "repr": "int32", "constants": constants,
                            "brief": brief}, ignore=("repr",))
        elif kind == CursorKind.STRUCT_DECL and cursor.is_definition() and \
                name.startswith("accesskit_"):
            aux = []
            fields = self.struct_fields(cursor, type_name(name), aux)
            for extra in aux:
                self.add("%s.%s" % (name, extra["nim_name"]), extra)
            self.add(name, {"kind": "struct", "nim_name": type_name(name),
                            "cname": name, "union": False, "fields": fields,
                            "brief": brief})
        elif kind == CursorKind.TYPEDEF_DECL and \
                name.startswith("accesskit_"):
            underlying = cursor.underlying_typedef_type
            canonical = underlying.get_canonical()
            if canonical.kind == TypeKind.ENUM:
                return  # typedef of the enum itself; keep int32 repr
            if canonical.kind == TypeKind.RECORD:
                record = canonical.get_declaration()
                if record.spelling in self.model:
                    if underlying.spelling.endswith(record.spelling) and \
                            not record.is_definition():
                        pass  # forward typedef handled below
                    else:
                        return  # struct definition already registered
                if not record.is_definition():
                    self.add(name, {"kind": "opaque",
                                    "nim_name": type_name(name),
                                    "brief": brief})
                return
            if name in self.model and self.model[name]["kind"] == "enum":
                # e.g. typedef uint8_t accesskit_role; sets the ABI type.
                enum = self.model[name]
                enum["repr"] = self.map_type(underlying)
                if self.platform not in enum["platforms"]:
                    enum["platforms"].append(self.platform)
                return
            if canonical.kind == TypeKind.POINTER and \
                    canonical.get_pointee().kind == TypeKind.FUNCTIONPROTO:
                proto = canonical.get_pointee()
                self.add(name, {
                    "kind": "callback", "nim_name": type_name(name),
                    "params": self.callback_params(cursor, proto),
                    "result": self.map_result(proto.get_result()),
                    "brief": brief})
                return
            self.add(name, {"kind": "alias", "nim_name": type_name(name),
                            "type": self.map_type(underlying),
                            "brief": brief})
        elif kind == CursorKind.FUNCTION_DECL and \
                name.startswith("accesskit_"):
            self.add(name, {"kind": "func", "nim_name": proc_name(name),
                            "cname": name, "params": self.params(cursor),
                            "result": self.map_result(cursor.result_type),
                            "brief": brief})
        elif kind == CursorKind.VAR_DECL and name.startswith("ACCESSKIT_"):
            self.add(name, {"kind": "var", "nim_name": const_name(name),
                            "cname": name,
                            "type": self.map_type(cursor.type),
                            "brief": brief})

    def parse(self, platform, target_args):
        self.platform = platform
        index = cindex.Index.create()
        tu = index.parse(HEADER,
                         args=COMMON_ARGS + resource_dir_args() + target_args)
        errors = [str(d) for d in tu.diagnostics if d.severity >=
                  cindex.Diagnostic.Error]
        if errors:
            raise RuntimeError("parse errors for %s:\n%s" %
                               (platform, "\n".join(errors)))
        for cursor in tu.cursor.get_children():
            if cursor.location.file and \
                    os.path.normcase(cursor.location.file.name) == \
                    os.path.normcase(HEADER):
                self.visit(cursor)


def find_libclang():
    path = os.environ.get("LIBCLANG_PATH")
    if path:
        return path
    clang_exe = shutil.which("clang")
    if clang_exe:
        for lib in ("libclang.dll", "libclang.so", "libclang.dylib"):
            candidate = os.path.join(os.path.dirname(clang_exe), lib)
            if os.path.exists(candidate):
                return candidate
    return None  # let cindex try its default lookup


def guard(platforms):
    platforms = frozenset(platforms)
    if platforms == ALL_PLATFORMS:
        return None
    return GUARDS[platforms]


def wrap(line, indent):
    # Breaks a generated line at commas to stay under ~90 columns.
    result = []
    prefix = " " * indent
    while len(line) > 90:
        cut = line.rfind(", ", 0, 88)
        if cut < 0:
            break
        result.append(line[:cut + 1])
        line = prefix + "    " + line[cut + 2:]
    result.append(line)
    return result


class Writer:
    def __init__(self):
        self.lines = []

    def emit(self, text, indent=0):
        for raw in text.split("\n"):
            line = (" " * indent + raw) if raw else ""
            if raw.lstrip().startswith("#"):
                self.lines.append(line)
            else:
                self.lines.extend(wrap(line, indent))

    def brief(self, decl, indent):
        if decl.get("brief"):
            self.emit("# " + " ".join(decl["brief"].split()), indent)

    def emit_type(self, decl, indent):
        self.brief(decl, indent)
        kind = decl["kind"]
        name = decl["nim_name"]
        if kind == "opaque":
            self.emit("%s* = object" % name, indent)
        elif kind == "alias":
            self.emit("%s* = %s" % (name, decl["type"]), indent)
        elif kind == "enum":
            self.emit("%s* = %s" % (name, decl["repr"]), indent)
        elif kind == "callback":
            params = ", ".join("%s: %s" % (p["name"], p["type"])
                               for p in decl["params"])
            result = (": " + decl["result"]) if decl["result"] else ""
            self.emit("%s* = proc(%s)%s {.cdecl.}" % (name, params, result),
                      indent)
        elif kind == "struct":
            pragma = " {.union.}" if decl["union"] else ""
            self.emit("%s*%s = object" % (name, pragma), indent)
            for field in decl["fields"]:
                self.emit("%s*: %s" % (field["name"], field["type"]),
                          indent + 2)

    def emit_consts(self, decl, indent):
        self.emit("const", indent)
        for constant in decl["constants"]:
            self.emit("%s* = %s(%d)" % (constant["name"], decl["nim_name"],
                                        constant["value"]), indent + 2)

    def emit_func(self, decl, indent):
        self.brief(decl, indent)
        params = ", ".join("%s: %s" % (p["name"], p["type"])
                           for p in decl["params"])
        result = (": " + decl["result"]) if decl["result"] else ""
        self.emit('proc %s*(%s)%s {.importc: "%s".}' %
                  (decl["nim_name"], params, result, decl["cname"]), indent)

    def emit_var(self, decl, indent):
        self.brief(decl, indent)
        self.emit('var %s* {.importc: "%s".}: %s' %
                  (decl["nim_name"], decl["cname"], decl["type"]), indent)


def grouped(decls):
    # Groups consecutive declarations sharing the same platform guard.
    groups = []
    for decl in decls:
        g = guard(decl["platforms"])
        if groups and groups[-1][0] == g:
            groups[-1][1].append(decl)
        else:
            groups.append((g, [decl]))
    return groups


def generate(model, order):
    decls = [model[name] for name in order]
    types = [d for d in decls if d["kind"] in
             ("opaque", "alias", "enum", "callback", "struct")]
    enums = [d for d in decls if d["kind"] == "enum" and d["constants"]]
    variables = [d for d in decls if d["kind"] == "var"]
    funcs = [d for d in decls if d["kind"] == "func"]

    w = Writer()
    w.emit('''\
## Nim bindings for the AccessKit C API (vendor/accesskit-c).
##
## Generated by tools/generate_accesskit_bindings.py from
## vendor/accesskit-c/include/accesskit.h. Do not edit manually; rerun the
## generator instead.
##
## AccessKit support is optional: the SDL3 host enables it when compiled
## with -d:nuiAccessKit (see nuigi_accesskit.nim and sdl3_app.nim). The
## library is loaded at runtime, so the prebuilt shared library from
## vendor/accesskit-c/lib must be next to the executable
## (`./build.exe accesskit` copies it).

const AccessKitLibName* =
  when defined(windows): "accesskit.dll"
  elif defined(macosx): "libaccesskit.dylib"
  else: "libaccesskit.so"

when defined(nimony):
  {.feature: "lenientnils".}
''')
    for g, group in grouped(types):
        if g is None:
            w.emit("type")
            for decl in group:
                w.emit_type(decl, 2)
        else:
            w.emit("when %s:" % g)
            w.emit("type", 2)
            for decl in group:
                w.emit_type(decl, 4)
        w.emit("")
    for g, group in grouped(enums):
        indent = 0
        if g is not None:
            w.emit("when %s:" % g)
            indent = 2
        for decl in group:
            w.brief(decl, indent)
            w.emit_consts(decl, indent)
            w.emit("")
    w.emit('''\
when defined(nimony):
  {.push callConv: cdecl.}
  {.passL: "-laccesskit".}
else:
  {.push callConv: cdecl, dynlib: AccessKitLibName.}
''')
    for g, group in grouped(variables + funcs):
        indent = 0
        if g is not None:
            w.emit("when %s:" % g)
            indent = 2
        for decl in group:
            if decl["kind"] == "var":
                w.emit_var(decl, indent)
            else:
                w.emit_func(decl, indent)
        w.emit("")
    w.emit("{.pop.}")
    return "\n".join(w.lines) + "\n"


def main():
    lib = find_libclang()
    if lib:
        cindex.Config.set_library_file(lib)
    parser = Parser()
    for platform, target_args in PLATFORMS:
        parser.parse(platform, target_args)
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump([parser.model[name] for name in parser.order], f, indent=1)
    nim = generate(parser.model, parser.order)
    with open(OUT_NIM, "w", encoding="utf-8", newline="\n") as f:
        f.write(nim)
    print("wrote %s (%d declarations, model: %s)" %
          (os.path.relpath(OUT_NIM, ROOT), len(parser.order),
           os.path.relpath(OUT_JSON, ROOT)))


if __name__ == "__main__":
    main()
