defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that auto-detects new Elixir tools/functions and appends
  their documentation to SKILL.md using a specific YAML frontmatter standard.
  """
  use GenServer
  require Logger

  # Run every 60 minutes
  @interval 60 * 60 * 1000
  @skill_file "SKILL.md"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update, state) do
    Task.start(fn -> update_skills() end)
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  def update_skills do
    Logger.info("Starting SkillTracker to update #{@skill_file}...")

    # Load modules starting with Elixir.GovernanceCore
    modules =
      :code.all_loaded()
      |> Enum.map(fn {mod, _} -> mod end)
      |> Enum.filter(fn mod ->
        String.starts_with?(Atom.to_string(mod), "Elixir.GovernanceCore")
      end)

    # Collect documentation
    docs =
      Enum.flat_map(modules, fn mod ->
        case Code.fetch_docs(mod) do
          {:docs_v1, _, _, _, _, _, function_docs} ->
            Enum.map(function_docs, fn
              {{:function, func_name, arity}, _, _, doc_map, _} ->
                doc_text = extract_doc(doc_map)
                %{module: mod, function: func_name, arity: arity, doc: doc_text}
              _ -> nil
            end) |> Enum.reject(&is_nil/1)

          _ ->
            []
        end
      end)
      # Only keep those with actual documentation
      |> Enum.filter(fn %{doc: doc} -> doc != "" end)

    # Format entries
    entries =
      Enum.map(docs, fn %{module: mod, function: func, arity: arity, doc: doc} ->
        # Ensure 1024-char limit for description
        truncated_doc = String.slice(doc, 0, 1024)

        # Properly indent multiline YAML block scalar
        indented_doc =
          truncated_doc
          |> String.split("\n")
          |> Enum.map(fn line -> "  #{line}" end)
          |> Enum.join("\n")

        """
        ---
        tool_name: #{inspect(mod)}.#{func}/#{arity}
        description: |
        #{indented_doc}
        ---
        """
      end)

    header = "# Auto-Generated Agent Skills\n\n"
    content = header <> Enum.join(entries, "\n")

    File.write!(@skill_file, content)
    Logger.info("SkillTracker updated #{@skill_file} with #{length(entries)} skills.")
  end

  defp extract_doc(%{"en" => doc}) when is_binary(doc), do: doc
  defp extract_doc(_), do: ""
end
