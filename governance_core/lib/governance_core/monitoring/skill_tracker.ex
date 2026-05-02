defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates and updates SKILL.md documentation dynamically based on
  available modules. Ensures files comply with 1024-character size limits.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000
  @max_chars 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_update()
    {:ok, state}
  end

  @impl true
  def handle_info(:update, state) do
    generate_skills_docs()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  def generate_skills_docs do
    Logger.debug("Starting SKILL.md generation sequence...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.map(&module_to_yaml/1)
        |> chunk_and_write_files()
      :undefined ->
        Logger.error("Failed to retrieve modules for GovernanceCore")
    end
  end

  defp module_to_yaml(module) do
    name = inspect(module)
    desc = get_module_doc(module)

    # Indent multiline descriptions line-by-line for YAML block scalars
    indented_desc =
      desc
      |> String.split("\n")
      |> Enum.map(fn line -> "    " <> line end)
      |> Enum.join("\n")

    """
    - name: #{name}
      description: |
    #{indented_desc}
    """
  end

  defp get_module_doc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, :elixir, "text/markdown", %{"en" => doc}, _, _} ->
        doc || "No description available."
      _ ->
        "No description available."
    end
  end

  defp chunk_and_write_files(yaml_blocks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    {files, current_chunk, _current_size} =
      Enum.reduce(yaml_blocks, {[], [], 0}, fn block, {files, current_chunk, size} ->
        block_size = String.length(block)
        if size + block_size > @max_chars and size > 0 do
          {files ++ [Enum.reverse(current_chunk)], [block], block_size}
        else
          {files, [block | current_chunk], size + block_size}
        end
      end)

    # Add the last chunk if not empty
    all_chunks =
      if Enum.empty?(current_chunk) do
        files
      else
        files ++ [Enum.reverse(current_chunk)]
      end

    Enum.with_index(all_chunks, 1)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(priv_dir, filename)

      content = "---\nskills:\n" <> Enum.join(chunk, "\n")

      case File.write(filepath, content) do
        :ok ->
          Logger.info("Successfully updated #{filename}")
        {:error, reason} ->
          Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
