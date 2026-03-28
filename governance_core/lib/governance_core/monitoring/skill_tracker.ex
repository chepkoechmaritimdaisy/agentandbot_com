defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Monitors newly loaded functions starting with `Elixir.GovernanceCore`,
  extracts docs, and generates YAML entries in `SKILL.md` (max 1024 chars).
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # every minute
  @skill_file "SKILL.md"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    update_skills()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  def update_skills do
    # Memory: "Tool documentation (SKILL.md) is dynamically managed in production via the GovernanceCore.Monitoring.SkillTracker GenServer (rather than a Mix task), which auto-detects new functions using Code.all_loaded() (filtered to modules starting with Elixir.GovernanceCore) and Code.fetch_docs/1 and appends entries with YAML frontmatter adhering to a 1024-character limit."

    modules =
      Code.all_loaded()
      |> Enum.map(fn {mod, _} -> mod end)
      |> Enum.filter(fn mod ->
        String.starts_with?(Atom.to_string(mod), "Elixir.GovernanceCore")
      end)

    docs_data =
      Enum.reduce(modules, [], fn mod, acc ->
        case Code.fetch_docs(mod) do
          {:docs_v1, _anno, _lang, _format, _module_doc, _metadata, docs} ->
            module_docs = extract_function_docs(mod, docs)
            acc ++ module_docs
          _ ->
            acc
        end
      end)

    # Convert to YAML format, max 1024 chars each
    yaml_entries = Enum.map(docs_data, &format_as_yaml/1)

    # In a real scenario we'd track what we've already written to avoid duplicates
    # For now, just rewrite or append. Let's append if not already in file.
    existing_content = if File.exists?(@skill_file), do: File.read!(@skill_file), else: ""

    new_entries =
      yaml_entries
      |> Enum.reject(fn entry -> String.contains?(existing_content, entry) end)

    unless Enum.empty?(new_entries) do
      content_to_add = Enum.join(new_entries, "\n\n")
      File.write!(@skill_file, "\n" <> content_to_add, [:append])
      Logger.info("SkillTracker: Added #{length(new_entries)} new skills to SKILL.md")
    end
  end

  defp extract_function_docs(mod, docs) do
    Enum.map(docs, fn
      {{:function, name, arity}, _anno, _sigs, %{"en" => doc_string}, _meta} ->
        %{module: mod, function: name, arity: arity, doc: doc_string}
      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp format_as_yaml(%{module: mod, function: name, arity: arity, doc: doc}) do
    # Memory: "When interpolating multiline strings into YAML block scalars (e.g., key: |), the injected string must be explicitly indented line-by-line in Elixir to maintain valid YAML structure."

    # Truncate doc string first to maintain valid YAML structure when enforcing 1024 char limit on the whole entry.
    # We estimate the overhead of the YAML structure to be around 100 chars, so we truncate doc early.
    max_doc_length = 900
    truncated_doc =
      if String.length(doc) > max_doc_length do
        String.slice(doc, 0, max_doc_length) <> "..."
      else
        doc
      end

    indented_doc =
      truncated_doc
      |> String.split("\n")
      |> Enum.map(fn line -> "  " <> line end)
      |> Enum.join("\n")

    """
    ---
    skill: #{inspect(mod)}.#{name}/#{arity}
    description: |
    #{indented_doc}
    ---
    """
  end
end
