(* https://github.com/The-Sequence-Ontology/Specifications/blob/master/gff3.md *)

open Base
open Printf

type record = {
  seqname    : string ;
  source     : string option ;
  feature    : string option ;
  start_pos  : int ;
  stop_pos   : int ;
  score      : float option ;
  strand     : [`Plus | `Minus | `Not_stranded | `Unknown ] ;
  phase      : int option ;
  attributes : (string * string list) list ;
}

type item = [ `Comment of string | `Record of record ]

let record
  ?source ?feature ?score ?(strand = `Unknown) ?phase ?(attributes = [])
  seqname start_pos stop_pos =
  {
    seqname ; source ; feature ; start_pos ; stop_pos ; score ; strand ; phase ; attributes ;
  }

let fail s = Error (`Msg s)

let parse_float s =
  try Ok (Float.of_string s)
  with Failure s -> fail s

let parse_int s =
  try Ok (Int.of_string s)
  with Failure s -> fail s

let parse_opt f = function
  | "." -> None
  | s -> Some (f s)

let parse_opt' f = function
  | "." -> Ok None
  | s ->
    Result.(f s >>| Option.some)

let parse_strand = function
  | "." -> Ok `Not_stranded
  | "?" -> Ok `Unknown
  | "+" -> Ok `Plus
  | "-" -> Ok `Minus
  | _ -> Error (`Msg "Incorrect strand character")

let parse_tag pos buf =
  match String.index_from buf pos '=' with
  | None -> fail "Tag without a value"
  | Some k ->
    Ok (k + 1, String.slice buf pos k)

let lfind_mapi ?(pos = 0) s ~f =
  let n = String.length s in
  let rec loop i =
    if i < n then
      match f i s.[i] with
      | None -> loop (i + 1)
      | Some y -> Some y
    else
      None
  in
  loop pos

let rec parse_value_list pos buf acc =
  let comma_or_semi_colon i = function
    | ',' -> Some (i, `Comma)
    | ';' -> Some (i, `Semi_colon)
    | _ -> None
  in
  match lfind_mapi ~pos buf ~f:comma_or_semi_colon with
  | None ->
    let n = String.length buf in
    let value = String.slice buf pos n in
    n, List.rev (value :: acc)
  | Some (k, `Comma) ->
    let value = String.slice buf pos k in
    parse_value_list (k + 1) buf (value :: acc)
  | Some (k, `Semi_colon) ->
    let value = String.slice buf pos k in
    k + 1, List.rev (value :: acc)

let rec parse_gff3_attributes pos buf acc =
  let open Result in
  if pos >= String.length buf then Ok (List.rev acc)
  else
    parse_tag pos buf >>= fun (pos, tag) ->
    let pos, values = parse_value_list pos buf [] in
    let acc = (tag, values) :: acc in
    parse_gff3_attributes pos buf acc

let parse_fields = function
  | [ seqname ; source ; feature ; start_pos ; stop_pos ;
      score ; strand ; phase ; attributes ] ->
    let open Result in
    parse_int start_pos >>= fun start_pos ->
    parse_int stop_pos >>= fun stop_pos ->
    parse_opt' parse_int phase >>= fun phase ->
    parse_opt' parse_float score >>= fun score ->
    parse_strand strand >>= fun strand ->
    parse_gff3_attributes 0 attributes [] >>= fun attributes ->
    Ok {
      seqname ;
      source = parse_opt Fn.id source ;
      feature = parse_opt Fn.id feature ;
      start_pos ;
      stop_pos ;
      score ;
      strand ;
      phase ;
      attributes ;
    }
  | _ -> fail "Incorrect number of fields"

let gff3_item_of_line line =
  match (line : Line.t :> string) with
  | "" -> fail "Empty line"
  | line ->
    if Char.(line.[0] = '#') then
      Ok (`Comment (String.slice line 1 0))
    else
      let open Result in
      let fields = String.split ~on:'\t' line in
      parse_fields fields >>| fun r ->
      `Record r

let line_of_item version = function
  | `Comment c -> Line.of_string_unsafe ("#" ^ c)
  | `Record t ->
    let escape =
      match version with
      | `three -> (fun s -> Uri.pct_encode s)
      | `two -> sprintf "%S"
    in
    let optescape o =  Option.value_map ~default:"." o ~f:escape in
    String.concat ~sep:"\t" [
      t.seqname ;
      optescape t.source ;
      Option.value ~default:"." t.feature ;
      Int.to_string t.start_pos ;
      Int.to_string t.stop_pos ;
      Option.value_map ~default:"." ~f:(sprintf "%g") t.score;
      (match t.strand with`Plus -> "+" | `Minus -> "-"
                        | `Not_stranded -> "." | `Unknown -> "?");
      Option.value_map ~default:"." ~f:(sprintf "%d") t.phase;
      String.concat ~sep:";"
        (List.map t.attributes ~f:(fun (k,v) ->
           match version with
           | `three ->
             sprintf "%s=%s" (Uri.pct_encode k)
               (List.map v ~f:Uri.pct_encode |> String.concat ~sep:",")
           | `two ->
             sprintf "%s %s" k
               (List.map v ~f:escape |> String.concat ~sep:",")
         ));
    ]
    |> Line.of_string_unsafe

