// Command design reads the design of Go packages for clerk: the types with their fields
// and methods, the package functions, and the names declared inside them. clerk_design.py
// builds it on first use and compares two of its outputs. It reads syntax only, so it
// needs no build of the code it reads and no module download.
//
//	design design <dir>...                 the design of each package directory
//	design uses <root> <pkg dir> <name>...  where code outside the package uses each name
//
// Paths are relative to the working directory. A name for `uses` is `pkg:<Name>` for a
// package-level type or function and `member:<Name>` for a field or a method.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type field struct {
	Name string `json:"name"`
	Type string `json:"type"`
	Tag  string `json:"tag"`
}

type typeDecl struct {
	Name   string  `json:"name"`
	Kind   string  `json:"kind"`
	File   string  `json:"file"`
	Fields []field `json:"fields"`
}

type funcDecl struct {
	Name     string   `json:"name"`
	Receiver string   `json:"receiver"`
	File     string   `json:"file"`
	Params   []field  `json:"params"`
	Results  []string `json:"results"`
	Locals   []string `json:"locals"`
}

type pkg struct {
	Dir   string     `json:"dir"`
	Name  string     `json:"name"`
	Types []typeDecl `json:"types"`
	Funcs []funcDecl `json:"funcs"`
}

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: design design <dir>... | design uses <root> <pkg dir> <name>...")
		os.Exit(2)
	}
	var out any
	switch os.Args[1] {
	case "design":
		out = design(os.Args[2:])
	case "uses":
		if len(os.Args) < 4 {
			fmt.Fprintln(os.Stderr, "usage: design uses <root> <pkg dir> <name>...")
			os.Exit(2)
		}
		out = uses(os.Args[2], os.Args[3], os.Args[4:])
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n", os.Args[1])
		os.Exit(2)
	}
	if err := json.NewEncoder(os.Stdout).Encode(out); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func design(dirs []string) []pkg {
	pkgs := []pkg{}
	for _, dir := range dirs {
		p := pkg{Dir: filepath.ToSlash(dir), Types: []typeDecl{}, Funcs: []funcDecl{}}
		files, _ := filepath.Glob(filepath.Join(dir, "*.go"))
		sort.Strings(files)
		for _, path := range files {
			if strings.HasSuffix(path, "_test.go") {
				continue
			}
			f, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ParseComments)
			if err != nil || ast.IsGenerated(f) {
				continue
			}
			if p.Name == "" {
				p.Name = f.Name.Name
			}
			readFile(&p, f, filepath.Base(path))
		}
		pkgs = append(pkgs, p)
	}
	return pkgs
}

func readFile(p *pkg, f *ast.File, file string) {
	for _, d := range f.Decls {
		switch d := d.(type) {
		case *ast.GenDecl:
			for _, s := range d.Specs {
				ts, ok := s.(*ast.TypeSpec)
				if !ok {
					continue
				}
				td := typeDecl{Name: ts.Name.Name, File: file, Fields: []field{}}
				switch t := ts.Type.(type) {
				case *ast.StructType:
					td.Kind = "struct"
					td.Fields = fields(t.Fields)
				case *ast.InterfaceType:
					td.Kind = "interface"
					td.Fields = fields(t.Methods)
				default:
					td.Kind = render(ts.Type)
				}
				p.Types = append(p.Types, td)
			}
		case *ast.FuncDecl:
			fd := funcDecl{Name: d.Name.Name, File: file, Params: fields(d.Type.Params),
				Results: []string{}, Locals: locals(d.Body)}
			if d.Recv != nil && len(d.Recv.List) > 0 {
				fd.Receiver = receiver(d.Recv.List[0].Type)
			}
			for _, r := range fields(d.Type.Results) {
				fd.Results = append(fd.Results, r.Type)
			}
			p.Funcs = append(p.Funcs, fd)
		}
	}
}

// receiver is the type a method belongs to, without the pointer or the type parameters.
func receiver(e ast.Expr) string {
	switch t := e.(type) {
	case *ast.StarExpr:
		return receiver(t.X)
	case *ast.IndexExpr:
		return receiver(t.X)
	case *ast.IndexListExpr:
		return receiver(t.X)
	case *ast.Ident:
		return t.Name
	}
	return render(e)
}

func render(e ast.Expr) string {
	switch t := e.(type) {
	case *ast.Ident:
		return t.Name
	case *ast.StarExpr:
		return "*" + render(t.X)
	case *ast.SelectorExpr:
		return render(t.X) + "." + t.Sel.Name
	case *ast.ArrayType:
		return "[]" + render(t.Elt)
	case *ast.MapType:
		return "map[" + render(t.Key) + "]" + render(t.Value)
	case *ast.IndexExpr:
		return render(t.X) + "[" + render(t.Index) + "]"
	case *ast.IndexListExpr:
		parts := []string{}
		for _, i := range t.Indices {
			parts = append(parts, render(i))
		}
		return render(t.X) + "[" + strings.Join(parts, ", ") + "]"
	case *ast.FuncType:
		return "func"
	case *ast.InterfaceType:
		return "interface"
	case *ast.StructType:
		return "struct"
	case *ast.Ellipsis:
		return "..." + render(t.Elt)
	case *ast.ChanType:
		return "chan " + render(t.Value)
	case *ast.ParenExpr:
		return render(t.X)
	}
	return "?"
}

func fields(fl *ast.FieldList) []field {
	out := []field{}
	if fl == nil {
		return out
	}
	for _, f := range fl.List {
		ty := render(f.Type)
		tag := ""
		if f.Tag != nil {
			if v, err := strconv.Unquote(f.Tag.Value); err == nil {
				tag = v
			}
		}
		if len(f.Names) == 0 {
			out = append(out, field{Type: ty, Tag: tag})
		}
		for _, n := range f.Names {
			out = append(out, field{Name: n.Name, Type: ty, Tag: tag})
		}
	}
	return out
}

func locals(body *ast.BlockStmt) []string {
	out := []string{}
	if body == nil {
		return out
	}
	seen := map[string]bool{}
	add := func(e ast.Expr) {
		if id, ok := e.(*ast.Ident); ok && id.Name != "_" {
			seen[id.Name] = true
		}
	}
	ast.Inspect(body, func(n ast.Node) bool {
		switch s := n.(type) {
		case *ast.AssignStmt:
			if s.Tok == token.DEFINE {
				for _, l := range s.Lhs {
					add(l)
				}
			}
		case *ast.RangeStmt:
			if s.Tok == token.DEFINE {
				add(s.Key)
				add(s.Value)
			}
		case *ast.ValueSpec:
			for _, id := range s.Names {
				add(id)
			}
		}
		return true
	})
	for k := range seen {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// usesResult says, for each name, which files outside its package use it. A use is
// counted from syntax alone: `alias.Name` against an import of the package for a
// package-level name, and any `.Name` selector or `Name:` key for a field or a method.
// The second over-counts, which keeps a name in the "used" column rather than reporting
// it as unused when it is not.
type usesResult struct {
	Uses             map[string][]string `json:"uses"`
	InterfaceMethods []string            `json:"interface_methods"`
	ImportPath       string              `json:"import_path"`
}

func uses(root, pkgDir string, names []string) usesResult {
	res := usesResult{Uses: map[string][]string{}, InterfaceMethods: []string{}}
	if abs, err := filepath.Abs(root); err == nil {
		root = abs
	}
	for _, n := range names {
		res.Uses[n] = []string{}
	}
	pkgDir = filepath.Clean(pkgDir)
	res.ImportPath = importPath(root, pkgDir)
	pkgName := packageName(filepath.Join(root, pkgDir))
	ifaces := map[string]bool{}

	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		name := d.Name()
		if d.IsDir() {
			if path != root && (name == "vendor" || name == "testdata" || name == "node_modules" ||
				strings.HasPrefix(name, ".") || strings.HasPrefix(name, "_")) {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			return nil
		}
		src, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		inPkg := filepath.Dir(rel) == pkgDir
		wanted := []string{}
		if !inPkg {
			for _, n := range names {
				if bytes.Contains(src, []byte(n[strings.Index(n, ":")+1:])) {
					wanted = append(wanted, n)
				}
			}
		}
		if len(wanted) == 0 && !bytes.Contains(src, []byte("interface")) {
			return nil
		}
		f, err := parser.ParseFile(token.NewFileSet(), path, src, parser.ParseComments)
		if err != nil || ast.IsGenerated(f) {
			return nil
		}
		collectInterfaceMethods(f, ifaces)
		if len(wanted) > 0 {
			for _, n := range usedIn(f, wanted, res.ImportPath, pkgName) {
				res.Uses[n] = append(res.Uses[n], filepath.ToSlash(rel))
			}
		}
		return nil
	})
	for m := range ifaces {
		res.InterfaceMethods = append(res.InterfaceMethods, m)
	}
	sort.Strings(res.InterfaceMethods)
	return res
}

func collectInterfaceMethods(f *ast.File, into map[string]bool) {
	ast.Inspect(f, func(n ast.Node) bool {
		if it, ok := n.(*ast.InterfaceType); ok && it.Methods != nil {
			for _, m := range it.Methods.List {
				for _, id := range m.Names {
					into[id.Name] = true
				}
			}
		}
		return true
	})
}

func usedIn(f *ast.File, wanted []string, imp, pkgName string) []string {
	alias := ""
	for _, is := range f.Imports {
		p, _ := strconv.Unquote(is.Path.Value)
		if imp != "" && p == imp {
			alias = pkgName
			if is.Name != nil {
				alias = is.Name.Name
			}
		}
	}
	found := map[string]bool{}
	ast.Inspect(f, func(n ast.Node) bool {
		switch x := n.(type) {
		case *ast.SelectorExpr:
			for _, w := range wanted {
				kind, name := w[:strings.Index(w, ":")], w[strings.Index(w, ":")+1:]
				if x.Sel.Name != name {
					continue
				}
				if kind == "member" {
					found[w] = true
					continue
				}
				if id, ok := x.X.(*ast.Ident); ok && alias != "" && id.Name == alias {
					found[w] = true
				}
			}
		case *ast.KeyValueExpr:
			if id, ok := x.Key.(*ast.Ident); ok {
				for _, w := range wanted {
					if strings.HasPrefix(w, "member:") && id.Name == w[len("member:"):] {
						found[w] = true
					}
				}
			}
		}
		return true
	})
	out := []string{}
	for w := range found {
		out = append(out, w)
	}
	sort.Strings(out)
	return out
}

// importPath is the package's import path from the nearest go.mod at or above it, or ""
// when there is none.
func importPath(root, pkgDir string) string {
	dir := filepath.Join(root, pkgDir)
	for d := dir; ; d = filepath.Dir(d) {
		data, err := os.ReadFile(filepath.Join(d, "go.mod"))
		if err == nil {
			for _, line := range strings.Split(string(data), "\n") {
				line = strings.TrimSpace(line)
				if strings.HasPrefix(line, "module ") {
					mod := strings.Trim(strings.TrimSpace(strings.TrimPrefix(line, "module")), `"`)
					rel, _ := filepath.Rel(d, dir)
					if rel == "." {
						return mod
					}
					return mod + "/" + filepath.ToSlash(rel)
				}
			}
			return ""
		}
		if d == filepath.Dir(d) || !strings.HasPrefix(d, filepath.Clean(root)) {
			return ""
		}
	}
}

func packageName(dir string) string {
	files, _ := filepath.Glob(filepath.Join(dir, "*.go"))
	for _, path := range files {
		if strings.HasSuffix(path, "_test.go") {
			continue
		}
		f, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.PackageClauseOnly)
		if err == nil {
			return f.Name.Name
		}
	}
	return filepath.Base(dir)
}
