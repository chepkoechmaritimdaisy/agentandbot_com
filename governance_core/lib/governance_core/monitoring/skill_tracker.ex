defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically reads application modules and generates standard YAML SKILL documentation,
  enforcing a 1024-character per file limit dynamically.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_tracking()
    {:ok, state}
  end

  def handle_info(:track, state) do
    perform_tracking()
    schedule_tracking()
    {:noreply, state}
  end

  defp schedule_tracking do
    Process.send_after(self(), :track, @interval)
  end

  def perform_tracking do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        yaml_blocks = generate_yaml_blocks(modules)
        chunks = chunk_by_size(yaml_blocks, 1024)
        write_chunks(chunks)
      _ ->
        Logger.error("Failed to read modules for SkillTracker")
    end
  end

  defp generate_yaml_blocks(modules) do
    Enum.map(modules, fn mod ->
      mod_string = inspect(mod)
      doc_string = get_module_doc(mod)

      # Proper YAML block scalar indentation
      indented_doc =
        doc_string
        |> String.split("\n")
        |> Enum.map(fn line -> "      #{line}" end)
        |> Enum.join("\n")

      """
      - module: #{mod_string}
        description: |
      #{indented_doc}
      """
    end)
  end

  defp get_module_doc(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, _, "text/markdown", %{"en" => doc}, _, _} -> doc
      _ -> "No documentation available."
    end
  end

  defp chunk_by_size(blocks, max_size) do
    Enum.reduce(blocks, [{[], 0}], fn block, acc ->
      [{current_chunk, current_size} | rest] = acc
      block_size = String.length(block)

      if current_size + block_size > max_size and current_size > 0 do
        # Start new chunk
        [{[block], block_size}, {current_chunk, current_size} | rest]
      else
        # Add to current chunk
        [{[block | current_chunk], current_size + block_size} | rest]
      end
    end)
    |> Enum.map(fn {chunk, _size} -> Enum.reverse(chunk) |> Enum.join("") end)
    |> Enum.reverse()
  end

  defp write_chunks(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {chunk_content, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(priv_dir, filename)

      case File.write(filepath, chunk_content) do
        :ok ->
          Logger.info("SkillTracker updated #{filename}")
        {:error, reason} ->
          Logger.error("SkillTracker failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
