(* $Id: iobase.ml,v 1.1 1998-09-01 14:32:04 ddr Exp $ *)

open Def;
open Gutil;

value magic_gwb = "GnWb001p";

value output_value_header_size = 20;
value output_value_no_sharing oc v =
  Marshal.to_channel oc v [Marshal.No_sharing]
;

value array_header_size arr =
  if Array.length arr < 8 then 1 else 5
;

value output_array_access oc arr pos =
  let rec loop pos i =
    if i == Array.length arr then pos
    else
      do output_binary_int oc pos; return
      loop (pos + Iovalue.size arr.(i)) (i + 1)
  in
  loop (pos + output_value_header_size + array_header_size arr) 0
;

value rec list_remove_assoc x =
  fun
  [ [(x1, y1) :: l] ->
      if x = x1 then l else [(x1, y1) :: list_remove_assoc x l]
  | [] -> [] ]
;

value array_memq x a =
  loop 0 where rec loop i =
    if i == Array.length a then False
    else if x == a.(i) then True
    else loop (i + 1)
;

(* Search index of a given string in file .gw2 *)

value int_size = 4;

value string_piece s =
  let s = String.escaped s in
  if String.length s > 20 then
    String.sub s 0 10 ^ " ... " ^ String.sub s (String.length s - 10) 10
  else s
;

value rec list_right_assoc s =
  fun
  [ [(i1, s1) :: l] -> if s = s1 then i1 else list_right_assoc s l
  | [] -> raise Not_found ]
;

value index_of_string strings ic start_pos hash_len string_patches s =
  try Adef.istr_of_int (list_right_assoc s string_patches.val) with
  [ Not_found ->
      let ia = Hashtbl.hash s mod hash_len in
      do seek_in ic (start_pos + ia * int_size); return
      let i1 = input_binary_int ic in
      loop i1 where rec loop i =
        if i == -1 then raise Not_found
        else
          if strings.get i = s then Adef.istr_of_int i
          else
            do seek_in ic (start_pos + (hash_len + i) * int_size);
            return loop (input_binary_int ic) ]
;

(* Search index of a given surname or given first name in file .gw2 *)

value compare_names = Gutil.alphabetique;
value compare_istr = ref (fun []);
value set_compare_istr base =
  compare_istr.val :=
    fun is1 is2 ->
      if is1 == is2 then 0
      else
        compare_names (base.strings.get (Adef.int_of_istr is1))
          (base.strings.get (Adef.int_of_istr is2))
;
module IstrTree =
  Btree.Make
    (struct type t = istr; value compare x y = compare_istr.val x y; end)
;

type first_name_or_surname_index = IstrTree.t (list iper);

value fsname_btree (ic2, start_pos, proj, person_patches, tree_name) =
  let btr = ref None in
  fun () ->
    match btr.val with
    [ Some bt -> bt
    | None ->
        do seek_in ic2 start_pos; return
        let bt : first_name_or_surname_index = input_value ic2 in
        let bt =
          List.fold_left
            (fun bt (i, p) ->
               let istr = proj p in
               let ipera =
                 try IstrTree.find istr bt with
                 [ Not_found -> [] ]
               in
               if List.memq p.cle_index ipera then bt
               else
                 IstrTree.add istr [ p.cle_index :: ipera] bt)
            bt person_patches.val
        in
        do btr.val := Some bt; return bt ]
;

value persons_of_first_name_or_surname strings params =
  let bt = fsname_btree params in
  let find istr = try IstrTree.find istr (bt ()) with [ Not_found -> [] ] in
  let cursor str =
    IstrTree.key_after
      (fun key -> compare_names str (strings.get (Adef.int_of_istr key)))
      (bt ())
  in
  let next key = IstrTree.next key (bt ()) in  
  {find = find; cursor = cursor; next = next}
;

(* Search index for a given name in file .inx *)

type name_index_data = array (array iper);

value persons_of_name bname patches =
  let t = ref None in
  fun s ->
    let s = Name.crush_lower s in
    let a =
      match t.val with
      [ Some a -> a
      | None ->
          let ic_inx = open_in_bin (Filename.concat bname "inx") in
          do seek_in ic_inx int_size; return
          let a = (input_value ic_inx : name_index_data) in
          do close_in ic_inx; t.val := Some a; return a ]
    in
    let i = Hashtbl.hash s in
    match patches.val with
    [ [] -> Array.to_list a.(i mod (Array.length a))
    | pl ->
        let l = try List.assoc i patches.val with [ Not_found -> [] ] in
        l @ Array.to_list a.(i mod (Array.length a)) ]
;

type strings_of_fsname = array (array istr);

value strings_of_fsname bname strings person_patches =
  let t = ref None in
  fun s ->
    let s = Name.crush_lower s in
    let a =
      match t.val with
      [ Some a -> a
      | None ->
          let ic_inx = open_in_bin (Filename.concat bname "inx") in
          let pos = input_binary_int ic_inx in
          do seek_in ic_inx pos; return
          let a = (input_value ic_inx : strings_of_fsname) in
          do close_in ic_inx; t.val := Some a; return a ]
    in
    let i = Hashtbl.hash s in
    let r = a.(i mod (Array.length a)) in
    match person_patches.val with
    [ [] -> Array.to_list r
    | _ ->
        let l =
          List.fold_left
            (fun l (_, p) ->
               let l =
                 if not (List.memq p.first_name l) then
                   let s1 = strings.get (Adef.int_of_istr p.first_name) in
                   if s = Name.crush_lower s1 then [p.first_name :: l] else l
                 else l
               in
               let l =
                 if not (List.memq p.surname l) then
                   let s1 = strings.get (Adef.int_of_istr p.surname) in
                   if s = Name.crush_lower s1 then [p.surname :: l] else l
                 else l
               in l)
            (Array.to_list r) person_patches.val
        in
        l ]
;

value lock_file bname =
  let bname =
    if Filename.check_suffix bname ".gwb" then
      Filename.chop_suffix bname ".gwb"
    else bname
  in
  bname ^ ".lck"
;

(* Input *)

value rec apply_patches tab =
  fun
  [ [] -> tab
  | [(i, v) :: l] ->
      let tab = apply_patches tab l in
      let tab =
        if i >= Array.length tab then
          let new_tab = Array.create (i + 1) (Obj.magic 0) in
          do Array.blit tab 0 new_tab 0 (Array.length tab); return
          new_tab
        else tab
      in
      do tab.(i) := v; return tab ]
;

value rec patch_len len =
  fun
  [ [] -> len
  | [(i, _) :: l] -> patch_len (max len (i + 1)) l ]
;

type patches =
  { p_person : ref (list (int * base_person));
    p_ascend : ref (list (int * base_ascend));
    p_family : ref (list (int * base_family));
    p_couple : ref (list (int * base_couple));
    p_string : ref (list (int * string));
    p_name : ref (list (int * list iper)) }
;

value check_magic =
  let b = String.create (String.length magic_gwb) in
  fun ic ->
    do really_input ic b 0 (String.length b); return
    if b <> magic_gwb then
      if String.sub magic_gwb 0 4 = String.sub b 0 4 then
        failwith "this is a GeneWeb base, but not compatible"
      else
        failwith "this is not a GeneWeb base, or it is a very old version"
    else ()
;

value make_cache ic ic_acc shift array_pos patches len name =
  let tab = ref None in
  let array () =
    match tab.val with
    [ Some x -> x
    | None ->
do ifdef UNIX then do Printf.eprintf "*** read %s\n" name; flush Pervasives.stderr; return () else (); return
        do seek_in ic array_pos; return
        let t = apply_patches (input_value ic) patches.val in
        do tab.val := Some t; return t ]
  in
  let r =
    {array = array; get = fun []; len = patch_len len patches.val}
  in
  let gen_get i =
    if tab.val <> None then (r.array ()).(i)
    else
      try List.assoc i patches.val with
      [ Not_found ->
          if i < 0 || i >= len then
            failwith ("access " ^ name ^ " out of bounds")
          else
            do seek_in ic_acc (shift + Iovalue.sizeof_long * i); return
            let pos = input_binary_int ic_acc in
            do seek_in ic pos; return
            Iovalue.input ic ]
  in
  do r.get := gen_get; return r
;

value make_cached ic ic_acc shift array_pos patches len cache_htab name =
  let tab = ref None in
  let array () =
    match tab.val with
    [ Some x -> x
    | None ->
do ifdef UNIX then do Printf.eprintf "*** read %s\n" name; flush Pervasives.stderr; return () else (); return
        do seek_in ic array_pos; return
        let t = apply_patches (input_value ic) patches.val in
        do tab.val := Some t; return t ]
  in
  let r =
    {array = array; get = fun []; len = patch_len len patches.val}
  in
  let gen_get i =
    if tab.val <> None then (r.array ()).(i)
    else
      try Hashtbl.find cache_htab i with
      [ Not_found ->
          let r =
            try List.assoc i patches.val with
            [ Not_found ->
                if i < 0 || i >= len then
                  failwith ("access " ^ name ^ " out of bounds")
                else
                  do seek_in ic_acc (shift + Iovalue.sizeof_long * i); return
                  let pos = input_binary_int ic_acc in
                  do seek_in ic pos; return
                  Iovalue.input ic ]
          in
          do Hashtbl.add cache_htab i r; return r ]
  in
  do r.get := gen_get; return r
;

value input bname =
  let bname =
    if Filename.check_suffix bname ".gwb" then bname
    else bname ^ ".gwb"
  in
  let patches =
    match
      try Some (open_in_bin (Filename.concat bname "gw9")) with _ -> None
    with
    [ Some ic ->
        let p = input_value ic in
        do close_in ic; return p
    | None ->
        {p_person = ref []; p_ascend = ref []; p_family = ref [];
         p_couple = ref []; p_string = ref []; p_name = ref []} ]
  in
  let ic = open_in_bin (Filename.concat bname "gwb") in
  do check_magic ic; return
  let ic_acc = open_in_bin (Filename.concat bname "acc") in
  let ic2 = open_in_bin (Filename.concat bname "gw2") in
  let persons_len = input_binary_int ic in
  let ascends_len = input_binary_int ic in
  let families_len = input_binary_int ic in
  let couples_len = input_binary_int ic in
  let strings_len = input_binary_int ic in
  let persons_array_pos = input_binary_int ic in
  let ascends_array_pos = input_binary_int ic in
  let families_array_pos = input_binary_int ic in
  let couples_array_pos = input_binary_int ic in
  let strings_array_pos = input_binary_int ic in
  let ic2_string_start_pos = 3 * int_size in
  let ic2_string_hash_len = input_binary_int ic2 in
  let ic2_surname_start_pos = input_binary_int ic2 in
  let ic2_first_name_start_pos = input_binary_int ic2 in
  let shift = 0 in
  let persons =
    make_cache ic ic_acc shift persons_array_pos patches.p_person persons_len
      "persons"
  in
  let shift = shift + persons_len * Iovalue.sizeof_long in
  let ascends =
    make_cache ic ic_acc shift ascends_array_pos patches.p_ascend ascends_len
      "ascends"
  in
  let shift = shift + ascends_len * Iovalue.sizeof_long in
  let families =
    make_cache ic ic_acc shift families_array_pos patches.p_family
      families_len "families"
  in
  let shift = shift + families_len * Iovalue.sizeof_long in
  let couples =
    make_cache ic ic_acc shift couples_array_pos patches.p_couple couples_len
      "couples"
  in
  let shift = shift + couples_len * Iovalue.sizeof_long in
  let strings_cache = Hashtbl.create 101 in
  let strings =
    make_cached ic ic_acc shift strings_array_pos patches.p_string strings_len
      strings_cache "strings"
  in
  let cleanup () =
    do close_in ic; close_in ic_acc; close_in ic2; return ()
  in
  let commit_patches () =
    let fname = Filename.concat bname "gw9" in
    do try Sys.remove (fname ^ "~") with _ -> ();
       try Sys.rename fname (fname ^ "~") with _ -> ();
    return
    let oc9 = open_out_bin fname in
    do output_value_no_sharing oc9 patches;
       close_out oc9;
    return ()
  in
  let patch_person i p =
    let i = Adef.int_of_iper i in
    do persons.len := max persons.len (i + 1);
       patches.p_person.val :=
         [(i, p) :: list_remove_assoc i patches.p_person.val];
    return ()
  in
  let patch_ascend i a =
    let i = Adef.int_of_iper i in
    do ascends.len := max ascends.len (i + 1);
       patches.p_ascend.val :=
         [(i, a) :: list_remove_assoc i patches.p_ascend.val];
    return ()
  in
  let patch_family i f =
    let i = Adef.int_of_ifam i in
    do families.len := max families.len (i + 1);
       patches.p_family.val :=
         [(i, f) :: list_remove_assoc i patches.p_family.val];
    return ()
  in
  let patch_couple i c =
    let i = Adef.int_of_ifam i in
    do couples.len := max couples.len (i + 1);
       patches.p_couple.val :=
         [(i, c) :: list_remove_assoc i patches.p_couple.val];
    return ()
  in
  let patch_string i s =
    let i = Adef.int_of_istr i in
    do strings.len := max strings.len (i + 1);
       patches.p_string.val :=
         [(i, s) :: list_remove_assoc i patches.p_string.val];
       Hashtbl.add strings_cache i s;
    return ()
  in
  let patch_name s ip =
    let s = Name.crush_lower s in
    let i = Hashtbl.hash s in
    let (ipl, name_patches_rest) =
      find patches.p_name.val where rec find =
        fun
        [ [] -> ([], [])
        | [(i1, ipl1) :: l] ->
            if i = i1 then (ipl1, l)
            else let (ipl, l) = find l in (ipl, [(i1, ipl1) :: l]) ]
    in
    if List.memq ip ipl then ()
    else patches.p_name.val := [(i, [ip :: ipl]) :: name_patches_rest]
  in
  let base =
    {persons = persons;
     ascends = ascends;
     families = families;
     couples = couples;
     strings = strings;
     persons_of_name = persons_of_name bname patches.p_name;
     strings_of_fsname = strings_of_fsname bname strings patches.p_person;
     has_family_patches =
       patches.p_family.val <> [] || patches.p_couple.val <> [];
     index_of_string =
       index_of_string strings ic2 ic2_string_start_pos ic2_string_hash_len
         patches.p_string;
     persons_of_surname =
       persons_of_first_name_or_surname strings
         (ic2, ic2_surname_start_pos, fun p -> p.surname, patches.p_person,
          "surname");
     persons_of_first_name =
       persons_of_first_name_or_surname strings
         (ic2, ic2_first_name_start_pos, fun p -> p.first_name,
          patches.p_person, "first_name");
     patch_person = patch_person;
     patch_ascend = patch_ascend;
     patch_family = patch_family;
     patch_couple = patch_couple;
     patch_string = patch_string;
     patch_name = patch_name;
     commit_patches = commit_patches; cleanup = cleanup}
  in
  do set_compare_istr base; return base
;

(* Output *)

value is_prime a =
  loop 2 where rec loop b =
    if a / b < b then True
    else if a mod b == 0 then False
    else loop (b + 1)
;

value rec prime_after n =
  if is_prime n then n else prime_after (n + 1)
;

value output_strings_hash oc2 base =
  let strings_array = base.strings.array () in
  let taba =
    Array.create (prime_after (max 2 (10 * Array.length strings_array))) (-1)
  in
  let tabl = Array.create (Array.length strings_array) (-1) in
  do for i = 0 to Array.length strings_array - 1 do
       let ia = Hashtbl.hash (strings_array.(i)) mod (Array.length taba) in
       do tabl.(i) := taba.(ia);
          taba.(ia) := i;
       return ();
     done;
  return
  do output_binary_int oc2 (Array.length taba);
     output_binary_int oc2 0;
     output_binary_int oc2 0;
     for i = 0 to Array.length taba - 1 do
       output_binary_int oc2 taba.(i);
     done;
     for i = 0 to Array.length tabl - 1 do
       output_binary_int oc2 tabl.(i);
     done;
  return ()
;

value create_first_name_or_surname_index base proj =
  let bt = ref IstrTree.empty in
  do set_compare_istr base;
     for i = 0 to base.persons.len - 1 do
       let p = base.persons.get i in
       let a =
         try IstrTree.find (proj p) bt.val with
         [ Not_found -> [] ]
       in
       bt.val :=
         IstrTree.add (proj p) [ p.cle_index :: a] bt.val;
     done;
  return bt.val
;

value output_surname_index oc2 base =
  let bt = create_first_name_or_surname_index base (fun p -> p.surname) in
  output_value_no_sharing oc2 (bt : first_name_or_surname_index)
;

value output_first_name_index oc2 base =
  let bt = create_first_name_or_surname_index base (fun p -> p.first_name) in
  output_value_no_sharing oc2 (bt : first_name_or_surname_index)
;

value table_size = 0x3fff;
value make_name_index base =
  let t = Array.create table_size [| |] in
  let a = base.persons.array () in
  let add_name key valu =
    let i = Hashtbl.hash (Name.crush (Name.abbrev key)) mod (Array.length t) in
    if array_memq valu t.(i) then ()
    else t.(i) := Array.append [| valu |] t.(i)
  in
  let rec add_names ip =
    fun
    [ [] -> ()
    | [n :: nl] -> do add_name n ip; return add_names ip nl ]
  in
  do for i = 0 to Array.length a - 1 do
       let p = base.persons.get i in
       let first_name = sou base p.first_name in
       let surname = sou base p.surname in
       if first_name <> "?" && surname <> "?" then
         let names =
           [Name.lower (first_name ^ " " ^ surname) ::
            person_misc_names base p]
         in
         add_names p.cle_index names
       else ();       
     done;
  return t
;

value create_name_index oc_inx base =
  let ni = make_name_index base in
  output_value_no_sharing oc_inx (ni : name_index_data)
;

value add_name t key valu =
  let i = Hashtbl.hash (Name.crush_lower key) mod (Array.length t) in
  if array_memq valu t.(i) then ()
  else t.(i) := Array.append [| valu |] t.(i)
;

value make_strings_of_fsname base =
  let t = Array.create table_size [||] in
  let a = base.persons.array () in
  do for i = 0 to Array.length a - 1 do
       let p = base.persons.get i in
       let first_name = sou base p.first_name in
       let surname = sou base p.surname in
       do if first_name <> "?" then add_name t first_name p.first_name
          else ();
          if surname <> "?" then add_name t surname p.surname
          else ();
       return ();
     done;
  return t
;

value create_strings_of_fsname oc_inx base =
  let t = make_strings_of_fsname base in
  output_value_no_sharing oc_inx (t : strings_of_fsname)
;

value count_error computed found =
  do Printf.eprintf "Count error. Computed %d. Found %d.\n" computed found;
     flush stderr;
  return exit 2
;

value output bname base =
  let bname =
    if Filename.check_suffix bname ".gwb" then bname
    else bname ^ ".gwb"
  in
  do try Unix.mkdir bname 0o755 with _ -> (); return
  let tmp_fname = Filename.concat bname "1wb" in
  let tmp_fname_acc = Filename.concat bname "1cc" in
  let tmp_fname_inx = Filename.concat bname "1nx" in
  let tmp_fname_gw2 = Filename.concat bname "1w2" in
  let _ = base.persons.array () in
  let _ = base.ascends.array () in
  let _ = base.families.array () in
  let _ = base.couples.array () in
  let _ = base.strings.array () in
  do base.cleanup (); return
  let oc = open_out_bin tmp_fname in
  let oc_acc = open_out_bin tmp_fname_acc in
  let oc_inx = open_out_bin tmp_fname_inx in
  let oc2 = open_out_bin tmp_fname_gw2 in
  let output_array arr =
    let bpos = pos_out oc in
    do output_value_no_sharing oc arr; return
    let epos = output_array_access oc_acc arr bpos in
    if epos <> pos_out oc then count_error epos (pos_out oc) else ()
  in
  try
    do output_string oc magic_gwb;
       output_binary_int oc base.persons.len;
       output_binary_int oc base.ascends.len;
       output_binary_int oc base.families.len;
       output_binary_int oc base.couples.len;
       output_binary_int oc base.strings.len;
    return
    let array_start_indexes = pos_out oc in
    do output_binary_int oc 0;
       output_binary_int oc 0;
       output_binary_int oc 0;
       output_binary_int oc 0;
       output_binary_int oc 0;
    return
    let persons_array_pos = pos_out oc in
    do output_array (base.persons.array ()); return
    let ascends_array_pos = pos_out oc in
    do output_array (base.ascends.array ()); return
    let families_array_pos = pos_out oc in
    do output_array (base.families.array ()); return
    let couples_array_pos = pos_out oc in
    do output_array (base.couples.array ()); return
    let strings_array_pos = pos_out oc in
    do output_array (base.strings.array ());
       seek_out oc array_start_indexes;
       output_binary_int oc persons_array_pos;
       output_binary_int oc ascends_array_pos;
       output_binary_int oc families_array_pos;
       output_binary_int oc couples_array_pos;
       output_binary_int oc strings_array_pos;
       close_out oc;
       close_out oc_acc;
do Printf.eprintf "*** create name index\n"; flush stderr; return
       output_binary_int oc_inx 0;
       create_name_index oc_inx base;
       let surname_or_first_name_pos = pos_out oc_inx in
do Printf.eprintf "*** create strings of fsname\n"; flush stderr; return
       do create_strings_of_fsname oc_inx base;
          seek_out oc_inx 0;
          output_binary_int oc_inx surname_or_first_name_pos;
          close_out oc_inx;
       return ();
do Printf.eprintf "*** create string index\n"; flush stderr; return
       output_strings_hash oc2 base;
       let surname_pos = pos_out oc2 in
do Printf.eprintf "*** create surname index\n"; flush stderr; return
       do output_surname_index oc2 base; return
       let first_name_pos = pos_out oc2 in
do Printf.eprintf "*** create first name index\n"; flush stderr; return
       do output_first_name_index oc2 base;
          seek_out oc2 int_size;
          output_binary_int oc2 surname_pos;
          output_binary_int oc2 first_name_pos;
       return ();
do Printf.eprintf "*** ok\n"; flush stderr; return
       close_out oc2;
       try Sys.remove (Filename.concat bname "gwb") with _ -> ();
       Sys.rename tmp_fname (Filename.concat bname "gwb");
       try Sys.remove (Filename.concat bname "acc") with _ -> ();
       Sys.rename tmp_fname_acc (Filename.concat bname "acc");
       try Sys.remove (Filename.concat bname "inx") with _ -> ();
       Sys.rename tmp_fname_inx (Filename.concat bname "inx");
       try Sys.remove (Filename.concat bname "gw2") with _ -> ();
       Sys.rename tmp_fname_gw2 (Filename.concat bname "gw2");
       try Sys.remove (Filename.concat bname "gw9") with _ -> ();
    return ()
  with e ->
    do try close_out oc with _ -> ();
       try close_out oc_acc with _ -> ();
       try close_out oc_inx with _ -> ();
       try close_out oc2 with _ -> ();
       try
         do Sys.remove tmp_fname;
            Sys.remove tmp_fname_acc;
            Sys.remove tmp_fname_inx;
            Sys.remove tmp_fname_gw2;
         return ()
       with _ -> ();
    return raise e
;
