(* $Id: i18n_check.ml,v 1.1 1998-09-01 14:32:12 ddr Exp $ *)

value usage () =
  do Printf.eprintf "Usage: i18n_check lang lexicon\n";
     flush stderr;
     exit 2;
  return ()
;

value main () =
  if Array.length Sys.argv <> 3 then usage ()
  else
    let lang = Sys.argv.(1) in
    let file = Sys.argv.(2) in
    let ic = open_in_bin file in
    try
      while True do
        let line_ref = input_line ic in
        loop (input_line ic) where rec loop line =
          if line = "" then ()
          else
            do if String.sub line 0 4 = lang ^ ": " then
                 Printf.printf "%s\n"
                   (String.sub line_ref 4 (String.length line_ref - 4))
               else ();
            return loop (input_line ic);
      done
    with [ End_of_file -> () ]
;

Printexc.catch main ();
