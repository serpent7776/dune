open Import

module Internal = struct
  type t = Path.t * Jbuild.Library.t
end

module T = struct
  type t =
    | Internal of Internal.t
    | External of Findlib.package

  let best_name = function
    | External pkg -> pkg.name
    | Internal (_, lib) ->
      match lib.public with
      | Some p -> p.name
      | None -> lib.name

  let compare a b = String.compare (best_name a) (best_name b)
end

include T
module Set = Set.Make(T)

module Source_dir = struct
  type t =
    | Internal
    | Install
end

let dir ~context ~source_dir = function
  | Internal (dir, lib) -> begin
      match lib.public, (source_dir : Source_dir.t) with
      | None, _ | _, Internal ->
        dir
      | Some { package; sub_dir; _ }, Install ->
        let install_dir = Config.local_install_dir ~context in
        let dir =  Path.append install_dir (Install.lib_install_path ~package) in
        match sub_dir with
        | None -> dir
        | Some x -> Path.relative dir x
    end
  | External pkg -> pkg.dir

let include_paths ~context ~source_dir ts =
  List.fold_left ts ~init:Path.Set.empty ~f:(fun acc t ->
    Path.Set.add (dir ~context ~source_dir t) acc)

let include_flags ~context ~source_dir ts =
  let dirs = include_paths ~context ~source_dir ts in
  Arg_spec.S (List.concat_map (Path.Set.elements dirs) ~f:(fun dir ->
    [Arg_spec.A "-I"; Path dir]))

let c_include_flags ~context ~source_dir ts =
  let dirs =
    List.fold_left ts ~init:Path.Set.empty ~f:(fun acc t ->
      Path.Set.add (dir ~context ~source_dir t) acc)
  in
  Arg_spec.S (List.concat_map (Path.Set.elements dirs) ~f:(fun dir ->
    [Arg_spec.A "-I"; Path dir]))

let describe = function
  | Internal (_, lib) ->
    sprintf "%s (local)"
      (match lib.public with
       | Some p -> p.name
       | None -> lib.name)
  | External pkg ->
    sprintf "%s (external)" pkg.name

let link_flags ~context ~source_dir ts ~mode =
  Arg_spec.S
    (include_flags ~context ~source_dir ts ::
     List.map ts ~f:(fun t ->
       match t with
       | External pkg ->
         Arg_spec.Deps_rel (pkg.dir, Mode.Dict.get pkg.archives mode)
       | Internal (dir, lib) ->
         Dep_rel (dir, lib.name ^ Mode.compiled_lib_ext mode)))

let archive_files ts ~mode ~ext_lib =
  List.concat_map ts ~f:(function
    | External pkg ->
      List.map (Mode.Dict.get pkg.archives mode) ~f:(Path.relative pkg.dir)
    | Internal (dir, lib) ->
      let l =
        [Path.relative dir (lib.name ^ Mode.compiled_lib_ext mode)]
      in
      if Jbuild.Library.has_stubs lib then
        Jbuild.Library.stubs_archive lib ~dir ~ext_lib :: l
      else
        l)

let jsoo_runtime_files ts =
  List.concat_map ts ~f:(function
    | External pkg ->
      List.map pkg.jsoo_runtime ~f:(Path.relative pkg.dir)
    | Internal (dir, lib) ->
      List.map lib.buildable.js_of_ocaml.javascript_files ~f:(Path.relative dir))
(*
let ppx_runtime_libraries ts =
  List.fold_left ts ~init:String_set.empty ~f:(fun acc t ->
    match t with
    | Internal (_, lib) ->
      String_set.union acc (String_set.of_list lib.ppx_runtime_libraries)
    | External pkg ->
      String_set.union acc (String_set.of_list pkg.ppx_runtime_deps))
*)

let remove_dups_preserve_order libs =
  let rec loop seen libs acc =
    match libs with
    | [] -> List.rev acc
    | lib :: libs ->
      let name = best_name lib in
      if String_set.mem name seen then
        loop seen libs acc
      else
        loop (String_set.add name seen) libs (lib :: acc)
  in
  loop String_set.empty libs []
;;
