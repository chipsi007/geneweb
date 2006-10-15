(* camlp4r ./pa_html.cmo *)
(* $Id: changeChildren.ml,v 5.13 2006-10-15 15:39:39 ddr Exp $ *)
(* Copyright (c) 1998-2006 INRIA *)

open Config;
open Def;
open Gutil;
open Gwdb;
open Util;

value print_child_person conf base p =
  let first_name = p_first_name base p in
  let surname = p_surname base p in
  let occ = get_occ p in
  let var = "c" ^ string_of_int (Adef.int_of_iper (get_key_index p)) in
  tag "table" "border=\"1\"" begin
    tag "tr" "align=\"%s\"" conf.left begin
      tag "td" begin
        Wserver.wprint "%s"
          (capitale (transl_nth conf "first name/first names" 0));
      end;
      tag "td" "colspan=\"3\"" begin
        xtag "input"
          "name=\"%s_first_name\" size=\"23\" maxlength=\"200\" value=\"%s\""
          var (quote_escaped first_name);
      end;
      tag "td" "align=\"%s\"" conf.right begin
        let s = capitale (transl conf "number") in Wserver.wprint "%s" s;
      end;
      tag "td" begin
        xtag "input" "name=\"%s_occ\" size=\"5\" maxlength=\"8\"%s" var
          (if occ = 0 then "" else " value=\"" ^ string_of_int occ ^ "\"");
      end;
    end;
    tag "tr" "align=\"%s\"" conf.left begin
      tag "td" begin
        Wserver.wprint "%s" (capitale (transl_nth conf "surname/surnames" 0));
      end;
      tag "td" "colspan=\"5\"" begin
        xtag "input"
          "name=\"%s_surname\" size=\"40\" maxlength=\"200\" value=\"%s\"" var
          surname;
      end;
    end;
  end
;

value select_children_of base u =
  List.fold_right
    (fun ifam ipl ->
       let des = doi base ifam in
       List.fold_right (fun ip ipl -> [ip :: ipl])
         (Array.to_list (get_children des)) ipl)
    (Array.to_list (get_family u)) []
;

value digest_children base ipl =
  let l =
    List.map
      (fun ip ->
         let p = poi base ip in
         (get_first_name p, get_surname p, get_occ p))
      ipl
  in
  Iovalue.digest l
;

value check_digest conf base digest =
  match p_getenv conf.env "digest" with
  [ Some ini_digest ->
      if digest <> ini_digest then Update.error_digest conf else ()
  | None -> () ]
;

value print_children conf base ipl =
  do {
    stagn "h4" begin
      Wserver.wprint "%s" (capitale (transl_nth conf "child/children" 1));
    end;
    tag "ul" begin
      List.iter
        (fun ip ->
           let p = poi base ip in
           tag "li" begin
             Wserver.wprint "%s"
               (reference conf base p (person_text conf base p));
             Wserver.wprint "%s\n" (Date.short_dates_text conf base p);
             print_child_person conf base p;
           end)
        ipl;
    end;
  }
;

value print_change conf base p u =
  let title _ =
    let s = transl conf "change children's names" in
    Wserver.wprint "%s" (capitale s)
  in
  let children = select_children_of base u in
  let digest = digest_children base children in
  do {
    header conf title;
    tag "p" begin
      Wserver.wprint "%s" (reference conf base p (person_text conf base p));
      Wserver.wprint "%s\n" (Date.short_dates_text conf base p);
    end;
    tag "form" "method=\"post\" action=\"%s\"" conf.command begin
      tag "p" begin
        Util.hidden_env conf;
        xtag "input" "type=\"hidden\" name=\"ip\" value=\"%d\""
          (Adef.int_of_iper (get_key_index p));
        xtag "input" "type=\"hidden\" name=\"digest\" value=\"%s\"" digest;
        xtag "input" "type=\"hidden\" name=\"m\" value=\"CHG_CHN_OK\"";
      end;
      print_children conf base children;
      Wserver.wprint "\n";
      tag "p" begin
        xtag "input" "type=\"submit\" value=\"Ok\"";
      end;
    end;
    Wserver.wprint "\n";
    trailer conf;
  }
;

value print conf base =
  match p_getint conf.env "ip" with
  [ Some i ->
      let p = poi base (Adef.iper_of_int i) in
      let u = uoi base (Adef.iper_of_int i) in
      print_change conf base p u
  | _ -> incorrect_request conf ]
;

value print_children_list conf base u =
  do {
    stag "h4" begin
      Wserver.wprint "%s" (capitale (transl_nth conf "child/children" 1));
    end;
    Wserver.wprint "\n<p>\n";
    tag "ul" begin
      Array.iter
        (fun ifam ->
           let des = doi base ifam in
           Array.iter
             (fun ip ->
                let p = poi base ip in
                do {
                  html_li conf;
                  Wserver.wprint "\n%s"
                    (reference conf base p (person_text conf base p));
                  Wserver.wprint "%s\n" (Date.short_dates_text conf base p);
                })
             (get_children des))
        (get_family u);
    end;
  }
;

value print_change_done conf base p u =
  let title _ =
    let s = transl conf "children's names changed" in
    Wserver.wprint "%s" (capitale s)
  in
  do {
    header conf title;
    Wserver.wprint "\n%s" (reference conf base p (person_text conf base p));
    Wserver.wprint "%s\n" (Date.short_dates_text conf base p);
    print_children_list conf base u;
    trailer conf;
  }
;

value print_conflict conf base p =
  let title _ = Wserver.wprint "%s" (capitale (transl conf "error")) in
  do {
    rheader conf title;
    Update.print_error conf base (AlreadyDefined p);
    html_p conf;
    Wserver.wprint "<ul>\n";
    html_li conf;
    Wserver.wprint "%s: %d\n" (capitale (transl conf "first free number"))
      (Gutil.find_free_occ base (p_first_name base p) (p_surname base p) 0);
    Wserver.wprint "</ul>\n";
    Update.print_same_name conf base p;
    trailer conf;
  }
;

value check_conflict conf base p key new_occ ipl =
  let name = Name.lower key in
  List.iter
    (fun ip ->
       let p1 = poi base ip in
       if get_key_index p1 <> get_key_index p &&
          Name.lower (p_first_name base p1 ^ " " ^ p_surname base p1) =
            name &&
          get_occ p1 = new_occ then
          do {
         print_conflict conf base p1; raise Update.ModErr
       }
       else ())
    ipl
;

value error_person conf base p err =
  let title _ = Wserver.wprint "%s" (capitale (transl conf "error")) in
  do {
    rheader conf title;
    Wserver.wprint "%s\n" (capitale err);
    trailer conf;
    raise Update.ModErr
  }
;

value rename_image_file conf base p (nfn, nsn, noc) =
  match auto_image_file conf base p with
  [ Some old_f ->
      let s = default_image_name_of_key nfn nsn noc in
      let f = Filename.concat (base_path ["images"] conf.bname) s in
      let new_f =
        if Filename.check_suffix old_f ".gif" then f ^ ".gif" else f ^ ".jpg"
      in
      try Sys.rename old_f new_f with [ Sys_error _ -> () ]
  | _ -> () ]
;

value change_child conf base parent_surname ip =
  let p = poi base ip in
  let var = "c" ^ string_of_int (Adef.int_of_iper (get_key_index p)) in
  let new_first_name =
    match p_getenv conf.env (var ^ "_first_name") with
    [ Some x -> only_printable x
    | _ -> p_first_name base p ]
  in
  let new_surname =
    match p_getenv conf.env (var ^ "_surname") with
    [ Some x ->
        let x = only_printable x in if x = "" then parent_surname else x
    | _ -> p_surname base p ]
  in
  let new_occ =
    match p_getint conf.env (var ^ "_occ") with
    [ Some x -> x
    | _ -> 0 ]
  in
  if new_first_name = "" then
    error_person conf base p (transl conf "first name missing")
  else if
    new_first_name <> p_first_name base p ||
    new_surname <> p_surname base p || new_occ <> get_occ p
  then do {
    let key = new_first_name ^ " " ^ new_surname in
    let ipl = person_ht_find_all base key in
    check_conflict conf base p key new_occ ipl;
    rename_image_file conf base p (new_first_name, new_surname, new_occ);
    let p =
      person_with_key p
        (Gwdb.insert_string base new_first_name)
        (Gwdb.insert_string base new_surname)
        new_occ
    in
    patch_person base (get_key_index p) p;
    person_ht_add base key (get_key_index p);
    let np_misc_names = person_misc_names base p (nobtit conf base) in
    List.iter (fun key -> person_ht_add base key (get_key_index p))
      np_misc_names;
  }
  else ()
;

value print_change_ok conf base p u =
  try
    let ipl = select_children_of base u in
    let parent_surname = p_surname base p in
    do {
      check_digest conf base (digest_children base ipl);
      List.iter (change_child conf base parent_surname) ipl;
      Util.commit_patches conf base;
      let key =
        (sou base (get_first_name p), sou base (get_surname p), get_occ p,
         get_key_index p)
      in
      History.record conf base key "cn";
      print_change_done conf base p u;
    }
  with
  [ Update.ModErr -> () ]
;

value print_ok conf base =
  match p_getint conf.env "ip" with
  [ Some i ->
      let p = poi base (Adef.iper_of_int i) in
      let u = uoi base (Adef.iper_of_int i) in
      print_change_ok conf base p u
  | _ -> incorrect_request conf ]
;
