defmodule GovernanceCore.Monitoring.SkillTracker do
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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
    Logger.info("SkillTracker: Updating SKILL.md documentation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        generate_skill_files(modules)

      _ ->
        Logger.error("SkillTracker: Failed to get modules for governance_core")
    end
  end

  defp generate_skill_files(modules) do
    # Group modules into chunks such that the generated YAML per chunk is under 1024 chars
    chunks = chunk_modules_by_yaml_length(modules, 1024)

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {chunk, index} ->
      yaml_content = generate_yaml(chunk)

      filename =
        if index == 1 do
          "SKILL.md"
        else
          "SKILL_#{index}.md"
        end

      path = Path.join(File.cwd!(), "priv/#{filename}")

      case File.write(path, yaml_content) do
        :ok ->
          Logger.info("SkillTracker: Wrote #{filename}")

        {:error, reason} ->
          Logger.error("SkillTracker: Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  defp chunk_modules_by_yaml_length(modules, max_length) do
    Enum.reduce(modules, [[]], fn mod, acc ->
      [current_chunk | rest] = acc

      # Test if adding this module exceeds the length
      test_chunk = current_chunk ++ [mod]

      if String.length(generate_yaml(test_chunk)) > max_length do
        if current_chunk == [] do
          # Single module is too big, still have to put it somewhere
          [[mod] | acc]
        else
          [[mod], current_chunk | rest]
        end
      else
        [test_chunk | rest]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(&Enum.reverse/1)
  end

  defp generate_yaml(modules) do
    header = "---\nskills:\n"

    items = Enum.map(modules, fn mod ->
      mod_string = inspect(mod)
      doc_string = get_module_doc(mod)

      # Multiline string must be explicitly indented line-by-line
      indented_doc =
        doc_string
        |> String.split("\n")
        |> Enum.map(&("      " <> &1))
        |> Enum.join("\n")

      """
        - module: #{mod_string}
          description: |
      #{indented_doc}
      """
    end)
    |> Enum.join("")

    header <> items <> "...\n"
  end

  defp get_module_doc(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} ->
        doc

      _ ->
        "No documentation available."
    end
  end
end
