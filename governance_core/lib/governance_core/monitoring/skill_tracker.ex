defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that auto-generates/updates SKILL.md documentation
  by scanning loaded `GovernanceCore` modules and generating entries
  in YAML format (with multiline string indentation and max 1024 chars per entry).
  """

  use GenServer
  require Logger

  @interval 60_000 # Default interval of 1 minute
  @skill_md_path "SKILL.md"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @interval)
    schedule_update(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:update, state) do
    Logger.info("Starting SkillTracker update...")
    update_skill_md()
    schedule_update(state.interval)
    {:noreply, state}
  end

  defp schedule_update(interval) do
    Process.send_after(self(), :update, interval)
  end

  def update_skill_md do
    modules =
      Code.all_loaded()
      |> Enum.map(fn {mod, _} -> mod end)
      |> Enum.filter(fn mod ->
        String.starts_with?(to_string(mod), "Elixir.GovernanceCore")
      end)

    docs =
      Enum.flat_map(modules, fn mod ->
        case Code.fetch_docs(mod) do
          {:docs_v1, _, :elixir, _format, %{"en" => mod_doc}, _metadata, docs} ->
            extract_docs(mod, mod_doc, docs)

          {:docs_v1, _, :elixir, _format, :none, _metadata, docs} ->
            extract_docs(mod, "", docs)

          _ ->
            []
        end
      end)

    content = Enum.join(docs, "\\n---\\n\\n")
    File.write!(@skill_md_path, content)
    Logger.info("SkillTracker updated SKILL.md successfully.")
  end

  defp extract_docs(mod, mod_doc, docs) do
    Enum.map(docs, fn
      {{:function, name, arity}, _anno, _signatures, %{"en" => doc}, _metadata} ->
        format_entry(mod, name, arity, doc)

      {{:function, name, arity}, _anno, _signatures, :none, _metadata} ->
        format_entry(mod, name, arity, "No documentation provided.")

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp format_entry(mod, name, arity, doc) do
    doc_indented =
      doc
      |> String.split("\\n")
      |> Enum.map(&"  #{&1}")
      |> Enum.join("\\n")

    yaml_entry = """
    name: #{mod}.#{name}/#{arity}
    description: |
    #{doc_indented}
    """

    # Enforce 1024-character limit
    String.slice(yaml_entry, 0, 1024)
  end
end
