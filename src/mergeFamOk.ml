(* camlp4r ./pa_html.cmo *)
(* $Id: mergeFamOk.ml,v 1.1 1998-09-01 14:32:11 ddr Exp $ *)

open Config;
open Def;
open Util;
open Gutil;

value reconstitute conf base fam1 fam2 =
  let field name proj null =
    let x1 = proj fam1 in
    let x2 = proj fam2 in
    match p_getenv conf.env name with
    [ Some "1" -> x1
    | Some "2" -> x2
    | _ -> if null x1 then x2 else x1 ]
  in
  {marriage = field "marriage" (fun f -> f.marriage) (\= Adef.codate_None);
   marriage_place =
     field "marriage_place" (fun f -> sou base f.marriage_place) (\= "");
   divorce = field "divorce" (fun f -> f.divorce) (\= NotDivorced);
   children =
     Array.map (UpdateFam.person_key base)
       (Array.append fam1.children fam2.children);
   comment = sou base fam1.comment;
   origin_file = sou base fam1.origin_file;
   fsources =
     let n1 = sou base fam1.fsources in
     let n2 = sou base fam2.fsources in
     if n1 = "" then n2
     else if n2 = "" then n1
     else n1 ^ ", " ^ n2;
   fam_index = fam1.fam_index}
;

value print_merge1 conf base fam fam2 digest =
  let title _ =
    Wserver.wprint "%s / %s # %d" (capitale (transl conf "merge"))
      (capitale (transl_nth conf "family/families" 1))
      (Adef.int_of_ifam fam.fam_index)
  in
  let cpl =
    Gutil.map_couple_p (UpdateFam.person_key base) (coi base fam.fam_index)
  in
  do header conf title;
     Wserver.wprint "\n";
     tag "form" "method=POST action=\"%s\"" conf.command begin
       Srcfile.hidden_env conf;
       Wserver.wprint "<input type=hidden name=m value=MRG_MOD_FAM_OK>\n";
       Wserver.wprint "<input type=hidden name=i value=%d>\n"
         (Adef.int_of_ifam fam.fam_index);
       Wserver.wprint "<input type=hidden name=digest value=\"%s\">\n" digest;
       Wserver.wprint "<input type=hidden name=i2 value=%d>\n"
         (Adef.int_of_ifam fam2.fam_index);
       match (p_getint conf.env "ini1", p_getint conf.env "ini2") with
       [ (Some i1, Some i2) ->
           do Wserver.wprint "<input type=hidden name=ini1 value=%d>\n" i1;
              Wserver.wprint "<input type=hidden name=ini2 value=%d>\n" i2;
           return ()
       | _ -> () ];
       Wserver.wprint "\n";
       UpdateFam.print_family conf base fam cpl False;
       Wserver.wprint "\n<p>\n";
       Wserver.wprint "<input type=submit value=Ok>\n";
     end;
     Wserver.wprint "\n";
     trailer conf;
  return ()
;

value print_merge conf base =
  match (p_getint conf.env "f1", p_getint conf.env "f2") with
  [ (Some f1, Some f2) ->
      let fam1 = base.families.get f1 in
      let fam2 = base.families.get f2 in
      let sfam = reconstitute conf base fam1 fam2 in
      let digest = Update.digest_family fam1 in
      print_merge1 conf base sfam fam2 digest
  | _ -> incorrect_request conf ]
;

value print_mod_merge_ok conf base wl fam cpl =
  let title _ =
    Wserver.wprint "%s" (capitale (transl conf "merge done"))
  in
  do header conf title;
     UpdateFamOk.print_family conf base wl fam cpl;
     match (p_getint conf.env "ini1", p_getint conf.env "ini2") with
     [ (Some ini1, Some ini2) ->
         let p1 = base.persons.get ini1 in
         let p2 = base.persons.get ini2 in
         do Wserver.wprint "\n<p>\n";
            stag "a" "href=%sm=MRG_IND;i=%d;i2=%d" (commd conf) ini1 ini2
            begin
              Wserver.wprint "%s" (capitale (transl conf "continue merging"));
            end;
            Wserver.wprint "\n";
            Merge.print_someone base p1;
            Wserver.wprint "\n%s\n" (transl conf "and");
            Merge.print_someone base p2;
            Wserver.wprint "\n";
         return ()
     | _ -> () ];
     trailer conf;
  return ()
;

value effective_mod_merge conf base sfam scpl =
  match p_getint conf.env "i2" with
  [ Some i2 ->
      let fam2 = base.families.get i2 in
      do UpdateFamOk.effective_del conf base fam2; return
      let (fam, cpl) = UpdateFamOk.effective_mod conf base sfam scpl in
      let wl = UpdateFamOk.all_checks_family conf base fam cpl in
      do base.commit_patches ();
         print_mod_merge_ok conf base wl fam cpl;
      return ()
  | None -> incorrect_request conf ]
;

value print_mod_merge conf base =
  UpdateFamOk.print_mod_aux conf base (effective_mod_merge conf base)
;
