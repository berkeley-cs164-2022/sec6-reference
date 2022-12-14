open Asm
open Lib
open Printf

type diffresult =
  { program : string
  ; expected: (string, string) result option
  ; interpreter: (string, string) result
  ; compiler: (string, string) result }

type partial_success = {interpreter_agrees: bool; compiler_agrees: bool}

let indent s =
  String.split_on_char '\n' s
  |> List.map (fun s -> "\t" ^ s)
  |> String.concat "\n"

let display_diffresult {program; expected; interpreter; compiler} : string =
  let display_outputs (outputs : (string * (string, string) result) list) =
    outputs
    |> List.map (fun (source, output) ->
           let descriptor, output =
             match output with
             | Ok output ->
                 ("output", output)
             | Error error ->
                 ("error", error)
           in
           sprintf "%s %s:\n\n%s" source descriptor (indent output))
    |> String.concat "\n\n"
  and expected =
    match expected with Some expected -> [("Expected", expected)] | None -> []
  and actual =
    [("Interpreter", interpreter); ("Compiler", compiler)]
  in
  sprintf "Program:\n\n%s\n\n" (indent program)
  ^ display_outputs (expected @ actual)

let outputs_agree expected actual =
  match (expected, actual) with
  | Ok expected, Ok actual ->
      String.equal expected actual
  | Error _, Error _ ->
      true
  | Ok _, Error _ | Error _, Ok _ ->
      false

let outputs_agree_modulo_undefined expected actual =
  match (expected, actual) with
  | Ok expected, Ok actual ->
      String.equal expected actual
  | Ok _, Error _ ->
      false
  | Error _, _ ->
      true

let result_of_diffresult diffresult =
  let ok, partial_success =
    match diffresult with
    | {program = _; expected= Some expected; interpreter; compiler} ->
        let interpreter_agrees = outputs_agree expected interpreter
        and compiler_agrees = outputs_agree_modulo_undefined expected compiler
        in
        ( interpreter_agrees && compiler_agrees
        , Some {interpreter_agrees; compiler_agrees} )
    | {program = _; expected= None; interpreter= Ok interpreter; compiler= Ok compiler} ->
        (String.equal interpreter compiler, None)
    | {program = _; expected = None; interpreter= _; compiler= _} ->
        (false, None)
  in
  let summary = display_diffresult diffresult in
  if ok then Ok summary else Error (summary, partial_success)

let diff name program _input expected =
  let ast =
    try Ok (S_exp.parse program) with e -> Error (Printexc.to_string e)
  in
  let try_run f =
    Result.bind ast (fun ast ->
        try Ok (f ast) with e -> Error (Printexc.to_string e))
  in
  let interpreter = try_run Interp.interp
  and compiler =
    try_run (fun ast ->
        let instrs = Compile.compile ast in
        Assemble.eval "test_output" Runtime.runtime name [] instrs)
  in
  result_of_diffresult {program; expected; interpreter; compiler}

let read_file file =
  let ch = open_in file in
  let s = really_input_string ch (in_channel_length ch) in
  close_in ch ;
  let n = String.length s in
  (* trim trailing newline if present *)
  if n > 0 && s.[n - 1] = '\n' then String.sub s 0 (n - 1) else s

let diff_file path : (string, string * partial_success option) result =
  let filename = Filename.basename path in
  let expected =
    let name = Filename.remove_extension path in
    let out_file = name ^ ".out" and err_file = name ^ ".err" in
    match (Sys.file_exists out_file, Sys.file_exists err_file) with
    | false, false ->
        None
    | false, true ->
        let reason = read_file err_file in
        let description =
          "ERROR"
          ^ if String.length reason > 0 then sprintf ": %s" reason else ""
        in
        Some (Error description)
    | true, false ->
        Some (Ok (read_file out_file))
    | true, true ->
        failwith (sprintf "Expected output and error for test: %s" filename)
  in
  let in_file = Filename.remove_extension path ^ ".in" in
  let input = if Sys.file_exists in_file then read_file in_file else "" in
  diff filename (read_file path) input expected

let csv_results =
  (try read_file "../examples/examples.csv" with _ -> "")
  |> String.split_on_char '\n'
  |> List.filter (fun line -> String.length line != 0)
  |> List.map (String.split_on_char ',')
  |> List.map (List.map String.trim)
  |> List.mapi (fun i ->
         let name = sprintf "anonymous-%d" i in
         function
         | [program] ->
             [(name, diff name program "" None)]
         | [program; (("error" | "ERROR") as error)] ->
             [(name, diff name program "" (Some (Error error)))]
         | [program; expected] ->
             [(name, diff name program "" (Some (Ok expected)))]
         | [program; input; (("error" | "ERROR") as error)] ->
             [(name, diff name program input (Some (Error error)))]
         | [program; input; expected] ->
             [(name, diff name program input (Some (Ok expected)))]
         | program :: pairs ->
             let rec diff_multiple i = function
               | [] ->
                   []
               | input :: expected :: rest ->
                   let name = sprintf "%s-%d" name i
                   and expected =
                     match expected with
                     | ("error" | "ERROR") as error ->
                         Error error
                     | output ->
                         Ok output
                   in
                   let result = diff name program input (Some expected) in
                   (name, result) :: diff_multiple (i + 1) rest
               | _ ->
                   failwith "invalid 'examples.csv' format"
             in
             diff_multiple 0 pairs
         | _ ->
             failwith "invalid 'examples.csv' format")
  |> List.concat


let file_results =
  Sys.readdir "../examples" |> Array.to_list
  |> List.filter (fun file -> Filename.check_suffix file ".lisp")
  |> List.map (sprintf "examples/%s")
  |> List.map (fun f -> (f, diff_file (sprintf "../%s" f)))

let results = file_results @ csv_results

let interp_passes res =
  begin match res with
    | Ok _ ->
        true

    | Error (_, Some partial) ->
        partial.interpreter_agrees

    | Error (_, None) ->
        false
  end

let compile_passes res =
  begin match res with
    | Ok _ ->
        true

    | Error (_, Some partial) ->
        partial.compiler_agrees

    | Error (_, None) ->
        false
  end

let difftest () =
  printf "TESTING\n" ;
  results
  |> List.iter (fun (filename, result) ->
         match result with
         | Error (summary, _) ->
             printf "\n=== Test failed: %s ===\n\n%s\n" filename summary
         | Ok _ ->
             ()) ;
  let num_tests = List.length results in
  let count f l =
    List.fold_left (fun count x -> if f x then 1 + count else count) 0 l
  in
  let failed_tests = count (fun (_, res) -> Result.is_error res) results in
  let interp_passed = count (fun (_, res) -> interp_passes res) results in
  let compile_passed = count (fun (_, res) -> compile_passes res) results in
  if failed_tests = 0 then
    printf "PASSED all %d tests\n" num_tests
  else
    printf "\nFAILED %d/%d tests\n(Interpreter passed %d/%d tests; Compiler passed %d/%d tests)"
    failed_tests num_tests interp_passed num_tests compile_passed num_tests

let difftest_json () =
  results
  |> List.map (fun (example, result) ->
         let details =
           match result with
           | Ok summary ->
               [("result", `String "passed"); ("summary", `String summary)]
           | Error (summary, partial_success) ->
               let partial_success =
                 match partial_success with
                 | None ->
                     []
                 | Some {interpreter_agrees; compiler_agrees} ->
                     [ ("interpreter_agrees", `Bool interpreter_agrees)
                     ; ("compiler_agrees", `Bool compiler_agrees) ]
               in
               [("result", `String "failed"); ("summary", `String summary)]
               @ partial_success
         in
         `Assoc (("example", `String example) :: details))
  |> fun elts -> `List elts

let () =
  match Sys.getenv_opt "DIFFTEST_OUTPUT" with
  | Some "json" ->
      difftest_json () |> Yojson.to_string |> printf "%s"
  | _ ->
      difftest ()
