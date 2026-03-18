defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically scans loaded modules for functions and their documentation,
  updating the SKILL.md file with YAML frontmatter to a maximum of 1024 characters
  per entry.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour
  @skill_file "SKILL.md"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update, state) do
    perform_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp perform_update do
    Logger.info("Starting SkillTracker update...")

    entries =
      Code.all_loaded()
      |> Enum.filter(fn {module, _} ->
        module |> to_string() |> String.starts_with?("Elixir.GovernanceCore")
      end)
      |> Enum.flat_map(fn {module, _} ->
        case Code.fetch_docs(module) do
          {:docs_v1, _, _, _, _, _, docs} ->
            extract_docs(module, docs)
          _ ->
            []
        end
      end)

    content = Enum.join(entries, "\n\n")
    File.write!(@skill_file, content)
    Logger.info("SkillTracker update completed.")
  end

  defp extract_docs(module, docs) do
    Enum.map(docs, fn
      {{:function, name, arity}, _anno, _sig, %{"en" => doc}, _metadata} ->
        format_entry(module, name, arity, doc)
      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp format_entry(module, name, arity, doc) do
    frontmatter = """
    ---
    module: #{inspect(module)}
    function: #{name}/#{arity}
    ---
    """

    # Ensure total length of frontmatter + doc is max 1024 chars
    max_doc_len = 1024 - String.length(frontmatter)

    truncated_doc =
      if String.length(doc) > max_doc_len do
        String.slice(doc, 0, max_doc_len - 3) <> "..."
      else
        doc
      end

    frontmatter <> truncated_doc
  end
end
