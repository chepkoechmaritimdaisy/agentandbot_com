defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automated GenServer to track new tools/functions and update SKILL.md.
  Scans all loaded Elixir.GovernanceCore modules and extracts documentation.
  """

  use GenServer
  require Logger

  @interval 60_000
  @max_yaml_len 1024

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_update()
    {:ok, %{last_known_funcs: []}}
  end

  @impl true
  def handle_info(:update_skills, state) do
    all_funcs = collect_functions()

    # We could compare with state.last_known_funcs here, but for simplicity
    # we'll just regenerate the file each time or append.
    # The requirement says "automatically creates or updates SKILL.md".
    generate_skill_md(all_funcs)

    schedule_update()
    {:noreply, %{state | last_known_funcs: all_funcs}}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  defp collect_functions do
    Code.all_loaded()
    |> Enum.filter(fn {mod, _file} ->
      mod |> to_string() |> String.starts_with?("Elixir.GovernanceCore")
    end)
    |> Enum.flat_map(fn {mod, _file} ->
      case Code.fetch_docs(mod) do
        {:docs_v1, _anno, _beam_lang, _format, _mod_doc, _meta, docs} ->
          Enum.map(docs, fn
            {{:function, name, arity}, _anno, _sigs, %{"en" => doc}, _meta} ->
              {mod, name, arity, doc}
            {{:function, name, arity}, _anno, _sigs, :none, _meta} ->
              {mod, name, arity, "No documentation."}
            _ ->
              nil
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end
    end)
  end

  defp generate_skill_md(functions) do
    content =
      functions
      |> Enum.map(&format_skill/1)
      |> Enum.join("\n\n")

    File.write!("SKILL.md", content)
  end

  defp format_skill({mod, name, arity, doc}) do
    # Ensure doc is indented properly for YAML multiline
    indented_doc =
      doc
      |> String.split("\n")
      |> Enum.map(fn line -> "  " <> line end)
      |> Enum.join("\n")

    yaml_entry = """
    ---
    module: #{inspect(mod)}
    function: #{name}/#{arity}
    description: |
    #{indented_doc}
    ---
    """

    # Ensure it meets the 1024-character limit
    if String.length(yaml_entry) > @max_yaml_len do
      String.slice(yaml_entry, 0, @max_yaml_len - 4) <> "\n---"
    else
      yaml_entry
    end
  end
end
