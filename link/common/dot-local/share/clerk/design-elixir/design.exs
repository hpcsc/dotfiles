# The design of Elixir code for clerk: the modules of each directory with their struct or
# schema fields and their functions, and the names declared inside the functions.
# clerk_design.py runs it with the Elixir of the repository and compares two of its outputs.
# It reads syntax only, so it needs no build of the code it reads and no dependency.
#
#     elixir design.exs design <root> <dir>...    the design of the .ex files in each directory
#
# A directory is relative to <root>. The output has the shape that the Go reader gives, so
# that one comparison reads both: a module is a type, and each of its functions is a
# function with the module as its receiver.

defmodule ClerkDesign do
  @definitions [:def, :defp, :defmacro, :defmacrop]
  @associations [:belongs_to, :has_one, :has_many, :many_to_many, :embeds_one, :embeds_many]

  def main(["design", root | dirs]) do
    dirs |> Enum.map(&package(root, &1)) |> json() |> IO.puts()
  end

  def main(_) do
    IO.puts(:stderr, "usage: elixir design.exs design <root> <dir>...")
    System.halt(2)
  end

  defp package(root, dir) do
    files = root |> Path.join(dir) |> Path.join("*.ex") |> Path.wildcard() |> Enum.sort()

    read =
      Enum.reduce(files, %{types: [], funcs: []}, fn path, acc ->
        with {:ok, source} <- File.read(path),
             {:ok, ast} <- Code.string_to_quoted(source) do
          read_forms(forms(ast), nil, Path.basename(path), acc)
        else
          _ -> acc
        end
      end)

    %{
      "dir" => dir,
      "name" => Path.basename(dir),
      "language" => "elixir",
      "types" => Enum.reverse(read.types),
      "funcs" => read.funcs |> Enum.reverse() |> Enum.uniq_by(&{&1["receiver"], &1["name"], &1["arity"]})
    }
  end

  defp forms({:__block__, _, forms}), do: forms
  defp forms(nil), do: []
  defp forms(form), do: [form]

  defp read_forms(forms, parent, file, acc) do
    Enum.reduce(forms, acc, fn
      {kind, _, [name, [do: body]]}, acc when kind in [:defmodule, :defprotocol] ->
        read_module(module_name(name, parent), kind, forms(body), file, acc)

      _, acc ->
        acc
    end)
  end

  defp read_module(name, kind, forms, file, acc) do
    acc = read_forms(forms, name, file, acc)
    type = %{"name" => name, "kind" => if(kind == :defprotocol, do: "protocol", else: "module"), "file" => file, "fields" => []}

    {type, funcs, _impl} =
      Enum.reduce(forms, {type, [], false}, fn form, {type, funcs, impl} ->
        case form do
          {:@, _, [{:impl, _, [value]}]} ->
            {type, funcs, value != false}

          {:@, _, [{:primary_key, _, [{:{}, _, [key, key_type, _]}]}]} ->
            {add_fields(type, nil, [field(key, key_type)]), funcs, impl}

          {struct, _, [fields]} when struct in [:defstruct, :defexception] ->
            {add_fields(type, kind_of(struct), struct_fields(fields)), funcs, impl}

          {schema, _, [_ | _] = args} when schema in [:schema, :embedded_schema] ->
            case List.last(args) do
              [do: body] -> {add_fields(type, "schema", Enum.flat_map(forms(body), &schema_fields/1)), funcs, impl}
              _ -> {type, funcs, impl}
            end

          {definition, _, [head | _]} when definition in @definitions ->
            {type, add_function(funcs, name, definition, head, form, file, impl or kind == :defprotocol), false}

          {:defdelegate, _, [head | _]} ->
            {type, add_function(funcs, name, :def, head, nil, file, false), false}

          _ ->
            {type, funcs, impl}
        end
      end)

    %{acc | types: [type | acc.types], funcs: funcs ++ acc.funcs}
  end

  defp module_name({:__aliases__, _, [{:__MODULE__, _, _} | rest]}, parent), do: join([parent | rest])
  defp module_name({:__aliases__, _, parts}, parent), do: join([parent | parts])
  defp module_name(atom, _parent) when is_atom(atom), do: atom |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  defp module_name(other, parent), do: join([parent, Macro.to_string(other)])

  defp join(parts), do: parts |> Enum.reject(&is_nil/1) |> Enum.map_join(".", &to_string/1)

  defp add_fields(type, nil, fields), do: %{type | "fields" => type["fields"] ++ fields}
  defp add_fields(type, kind, fields), do: %{type | "kind" => kind, "fields" => type["fields"] ++ fields}

  defp kind_of(:defstruct), do: "struct"
  defp kind_of(:defexception), do: "exception"

  defp struct_fields(fields) when is_list(fields), do: Enum.map(fields, &struct_field/1)
  defp struct_fields(_), do: []

  defp struct_field({name, _default}) when is_atom(name), do: field(name, nil)
  defp struct_field(name) when is_atom(name), do: field(name, nil)
  defp struct_field(other), do: field(Macro.to_string(other), nil)

  defp schema_fields({:field, _, [name | rest]}), do: [field(name, List.first(rest))]
  defp schema_fields({assoc, _, [name, module | _]}) when assoc in @associations, do: [field(name, module)]

  defp schema_fields({:timestamps, _, args}) when is_list(args) do
    opts = if Keyword.keyword?(List.first(args) || []), do: List.first(args) || [], else: []
    for key <- [:inserted_at, :updated_at], Keyword.get(opts, key) != false, do: field(Keyword.get(opts, key, key), nil)
  end

  defp schema_fields(_), do: []

  defp field(name, type), do: %{"name" => to_string(name), "type" => render(type), "tag" => ""}

  defp render(nil), do: ""
  defp render(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp render(other), do: Macro.to_string(other)

  defp add_function(funcs, module, definition, head, form, file, callback) do
    case call(head) do
      {name, args} ->
        [
          %{
            "name" => Atom.to_string(name),
            "arity" => length(args),
            "receiver" => module,
            "file" => file,
            "params" => Enum.map(args, &param/1),
            "results" => [],
            "locals" => locals(form),
            "exported" => definition in [:def, :defmacro],
            "impl" => callback
          }
          | funcs
        ]

      nil ->
        funcs
    end
  end

  defp call({:when, _, [head | _]}), do: call(head)
  defp call({name, _, args}) when is_atom(name) and is_list(args), do: {name, args}
  defp call({name, _, context}) when is_atom(name) and is_atom(context), do: {name, []}
  defp call(_), do: nil

  defp param({:\\, _, [arg, _default]}), do: param(arg)

  defp param({:=, _, [left, right]}) do
    case {param(left), param(right)} do
      {%{"name" => ""}, named} -> named
      {named, _} -> named
    end
  end

  defp param({name, _, context}) when is_atom(name) and is_atom(context) do
    if String.starts_with?(Atom.to_string(name), "_"), do: pattern(), else: %{"name" => Atom.to_string(name), "type" => ""}
  end

  defp param(_), do: pattern()

  defp pattern, do: %{"name" => "", "type" => "pattern"}

  defp locals(nil), do: []

  defp locals({_, _, [_head | rest]}) do
    {_, names} =
      Macro.prewalk(rest, MapSet.new(), fn
        {op, _, [left, _]} = node, names when op in [:=, :<-] -> {node, MapSet.union(names, variables(left))}
        node, names -> {node, names}
      end)

    names |> MapSet.to_list() |> Enum.sort()
  end

  defp variables(pattern) do
    {_, names} =
      Macro.prewalk(pattern, MapSet.new(), fn
        {:^, _, _}, names ->
          {nil, names}

        {name, _, context} = node, names when is_atom(name) and is_atom(context) ->
          text = Atom.to_string(name)
          if String.starts_with?(text, "_") or String.starts_with?(text, "__"), do: {node, names}, else: {node, MapSet.put(names, text)}

        node, names ->
          {node, names}
      end)

    names
  end

  defp json(nil), do: "null"
  defp json(true), do: "true"
  defp json(false), do: "false"
  defp json(n) when is_integer(n), do: Integer.to_string(n)
  defp json(s) when is_binary(s), do: "\"" <> escape(s) <> "\""
  defp json(list) when is_list(list), do: "[" <> Enum.map_join(list, ",", &json/1) <> "]"
  defp json(map) when is_map(map), do: "{" <> Enum.map_join(map, ",", fn {k, v} -> json(to_string(k)) <> ":" <> json(v) end) <> "}"

  defp escape(s) do
    for <<c::utf8 <- s>>, into: "" do
      case c do
        ?" -> "\\\""
        ?\\ -> "\\\\"
        ?\n -> "\\n"
        ?\r -> "\\r"
        ?\t -> "\\t"
        c when c < 0x20 -> "\\u" <> String.pad_leading(Integer.to_string(c, 16), 4, "0")
        c -> <<c::utf8>>
      end
    end
  end
end

ClerkDesign.main(System.argv())
