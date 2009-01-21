open Ocamlbuild_plugin
open Command

(* these functions are not really officially exported *)
let run_and_read = Ocamlbuild_pack.My_unix.run_and_read
let blank_sep_strings = Ocamlbuild_pack.Lexers.blank_sep_strings
  
(* this lists all supported packages *)
let find_packages () =
  blank_sep_strings &
    Lexing.from_string &
    run_and_read "ocamlfind list | cut -d' ' -f1"
    
(* this is supposed to list available syntaxes, but I don't know how to do it. *)
let find_syntaxes () = ["camlp4o"; "camlp4r"]

(* ocamlfind command *)
let ocamlfind x = S[A"ocamlfind"; x]

let _ = dispatch begin function
  | Before_options ->
      (* by using Before_options one let command line options have an higher priority *)
      (* on the contrary using After_options will guarantee to have the higher priority *)

      (* override default commands by ocamlfind ones *)
      Options.ocamlc   := ocamlfind & A"ocamlc";
      Options.ocamlopt := ocamlfind & A"ocamlopt";
      Options.ocamldep := ocamlfind & A"ocamldep";
      Options.ocamldoc := ocamlfind & A"ocamldoc"

  | After_rules ->

(* Delete this section once you are sure findlib based installations working fine. ****
      ocaml_lib ~extern:true ~dir:"../../lib" "tylesBase";
      flag ["ocaml"; "doc"] (S[A"-I";A"../../lib"]);
      flag ["ocaml"; "link"; "library"; "byte"] (A"../../lib/tylesBase.cma");
      flag ["ocaml"; "link"; "library"; "native"] (A"../../lib/tylesBase.cmx");
*)

      flag ["ocaml"; "parser"; "menhir"] (A"--explain");

      (* Add pa_openin.cmo to the ocaml pre-processor when use_opening is set *)
      flag ["ocaml"; "pp"; "use_openin"] (A"pa_openin.cmo");
      
      (* Running ocamldep on ocaml code that is tagged with use_openin will require the cmo.
         Note that you only need this declaration when the syntax extension is part of the
         sources to be compiled with ocamlbuild. *)
      dep ["ocaml"; "ocamldep"; "use_openin"] ["pa_openin.cmo"];
      
      (* When one link an OCaml library/binary/package, one should use -linkpkg *)
      flag ["ocaml"; "link"] & A"-linkpkg";
      
      (* For each ocamlfind package one inject the -package option when
       * compiling, computing dependencies, generating documentation and
       * linking. *)
      List.iter begin fun pkg ->
        flag ["ocaml"; "compile";  "pkg_"^pkg] & S[A"-package"; A pkg];
        flag ["ocaml"; "ocamldep"; "pkg_"^pkg] & S[A"-package"; A pkg];
        flag ["ocaml"; "doc";      "pkg_"^pkg] & S[A"-package"; A pkg];
        flag ["ocaml"; "link";     "pkg_"^pkg] & S[A"-package"; A pkg];
      end (find_packages ());
      
      (* Like -package but for extensions syntax. Morover -syntax is useless
       * when linking. *)
      List.iter begin fun syntax ->
        flag ["ocaml"; "compile";  "syntax_"^syntax] & S[A"-syntax"; A syntax];
        flag ["ocaml"; "ocamldep"; "syntax_"^syntax] & S[A"-syntax"; A syntax];
        flag ["ocaml"; "doc";      "syntax_"^syntax] & S[A"-syntax"; A syntax];
      end (find_syntaxes ());
      
      (* The default "thread" tag is not compatible with ocamlfind.
         Indeed, the default rules add the "threads.cma" or "threads.cmxa"
         options when using this tag. When using the "-linkpkg" option with
         ocamlfind, this module will then be added twice on the command line.
         
         To solve this, one approach is to add the "-thread" option when using
         the "threads" package using the previous plugin.
      *)
      flag ["ocaml"; "pkg_threads"; "compile"] (S[A "-thread"]);
      flag ["ocaml"; "pkg_threads"; "link"] (S[A "-thread"])
        
  | _ -> ()
end
