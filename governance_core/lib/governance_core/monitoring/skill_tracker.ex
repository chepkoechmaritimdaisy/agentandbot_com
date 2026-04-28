defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically generates SKILL.md files dynamically documenting modules.
  """
  use GenServer
  require Logger

  # 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp update_skills do
    Logger.info("Running SkillTracker update...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    chunks = chunk_modules_by_length(modules, 1024)

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.with_index(chunks, fn chunk, index ->
      filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
      filepath = Path.join(priv_dir, filename)

      yaml_content = "modules:\n" <> Enum.join(chunk, "")

      case File.write(filepath, yaml_content) do
        :ok ->
          Logger.debug("Wrote #{filename}")
        {:error, reason} ->
          Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  defp chunk_modules_by_length(modules, max_length) do
    yaml_entries = Enum.map(modules, &generate_yaml_entry/1)

    # "modules:\n" is 9 characters
    {chunks, current_chunk, _current_length} =
      Enum.reduce(yaml_entries, {[], [], 9}, fn entry, {completed_chunks, current_chunk, current_length} ->
        entry_length = String.length(entry)

        # If adding this entry exceeds max length (and it's not the first entry), start a new chunk
        if current_length + entry_length > max_length and current_length > 9 do
          {[Enum.reverse(current_chunk) | completed_chunks], [entry], 9 + entry_length}
        else
          {completed_chunks, [entry | current_chunk], current_length + entry_length}
        end
      end)

    chunks = if current_chunk != [], do: [Enum.reverse(current_chunk) | chunks], else: chunks
    Enum.reverse(chunks)
  end

  defp generate_yaml_entry(mod) do
    doc = get_module_doc(mod)

    indented_doc =
      doc
      |> String.split("\n")
      |> Enum.map(fn line -> "    " <> line end)
      |> Enum.join("\n")

    "  - name: #{inspect(mod)}\n    description: |\n#{indented_doc}\n"
  end

  defp get_module_doc(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, :elixir, "text/markdown", %{"en" => doc}, _, _} ->
        doc
      _ ->
        "No documentation available."
    end
  end
end
