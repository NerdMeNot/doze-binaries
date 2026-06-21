// Command dzb is the build-orchestration tool for doze-binaries. It has two
// subcommands used by the release workflow:
//
//	dzb plan                       resolve upstream versions -> CI build matrix JSON
//	dzb manifest <dist> <baseURL>  scan built archives -> multi-engine index.json
//
// The heavier lifting (compiling engines, bundling libraries, packaging) stays
// in shell, which is the better tool for orchestrating CLIs. dzb owns only the
// data work — version resolution and the manifest schema — where Go's types and
// testability pay off.
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fatal("usage: dzb <plan|manifest> [args]")
	}
	var err error
	switch os.Args[1] {
	case "plan":
		err = runPlan(os.Args[2:])
	case "manifest":
		err = runManifest(os.Args[2:])
	default:
		fatal("unknown command %q (want plan|manifest)", os.Args[1])
	}
	if err != nil {
		fatal("%v", err)
	}
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "dzb: "+format+"\n", args...)
	os.Exit(1)
}
