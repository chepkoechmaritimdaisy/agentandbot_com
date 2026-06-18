defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically tracks and updates SKILL.md documentation for application features
  and tools, adhering to universal standards like 1024 char limits and YAML format.
  """
  use GenServer
  require Logger

  # Update every 6 hours
  @interval 6 * 60 * 60 * 1000
  @max_chars 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update_skills, state) do
    update_skill_docs()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  def update_skill_docs do
    Logger.info("Updating SKILL.md documentation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.map(&module_to_tool_info/1)
        |> Enum.reject(&is_nil/1)
        |> chunk_and_write()

      _ ->
        Logger.error("Failed to fetch modules for SKILL.md generation.")
    end
  end

  defp module_to_tool_info(mod) do
    mod_name = inspect(mod)

    # Simplified heuristic: grab @moduledoc or default
    doc =
      case Code.fetch_docs(mod) do
        {:docs_v1, _, :elixir, "text/markdown", %{"en" => mod_doc}, _, _} -> mod_doc
        _ -> "No description available."
      end

    %{
      "tool" => mod_name,
      "description" => String.slice(doc, 0..100)
    }
  end

  defp chunk_and_write(tools) do
    base_path = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(base_path)

    tools
    |> split_into_chunks([])
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, index} ->
      file_name = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join(base_path, file_name)

      yaml_content = "---\n" <> to_yaml(chunk) <> "...\n"
      File.write!(file_path, yaml_content)
      Logger.info("Wrote #{file_name} successfully.")
    end)
  end

  defp split_into_chunks([], acc), do: Enum.reverse(acc)
  defp split_into_chunks(tools, acc) do
    {chunk, rest} = take_chunk(tools, [], 0)
    split_into_chunks(rest, [chunk | acc])
  end

  defp take_chunk([], chunk, _size), do: {Enum.reverse(chunk), []}
  defp take_chunk([tool | rest] = tools, chunk, current_size) do
    yaml_item = to_yaml([tool])
    item_size = String.length(yaml_item)

    if current_size + item_size > @max_chars and chunk != [] do
      {Enum.reverse(chunk), tools}
    else
      take_chunk(rest, [tool | chunk], current_size + item_size)
    end
  end

  # Extremely naive YAML formatter for demonstration purposes
  defp to_yaml(items) do
    Enum.map_join(items, "\n", fn item ->
      "- tool: #{item["tool"]}\n  description: #{inspect(item["description"])}"
    end) <> "\n"
  end
end
