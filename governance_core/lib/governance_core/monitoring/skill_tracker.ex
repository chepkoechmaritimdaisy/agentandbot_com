defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer that tracks application modules and generates standard SKILL.md
  documentation files within a 1024 character limit per file.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000
  @max_chars 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    # Trigger an initial update
    send(self(), :update_skills)
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

  defp update_skill_docs do
    Logger.info("Starting SKILL.md documentation generation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.map(&format_module_info/1)
        |> chunk_and_write()

      :undefined ->
        Logger.error("Failed to retrieve modules for :governance_core")
    end
  end

  defp format_module_info(module) do
    # Simple generation: Module name and attributes if available
    name = inspect(module)
    docs = get_docs(module)

    # Note: explicitly indenting multiline string line-by-line for YAML compliance
    indented_docs =
      docs
      |> String.split("\n")
      |> Enum.map(fn line -> "    " <> line end)
      |> Enum.join("\n")

    """
    - name: #{name}
      description: |
    #{indented_docs}
    """
  end

  defp get_docs(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, :elixir, _, %{"en" => docs}, _, _} ->
        docs

      _ ->
        "No documentation available."
    end
  end

  defp chunk_and_write(formatted_modules) do
    # Dynamically calculate length and chunk to enforce 1024 char limit
    chunks =
      Enum.reduce(formatted_modules, [{[], 0}], fn mod_str, acc ->
        [{current_chunk, current_len} | rest] = acc
        mod_len = String.length(mod_str)

        if current_len + mod_len > @max_chars and current_len > 0 do
          # Start a new chunk
          [{[mod_str], mod_len}, {current_chunk, current_len} | rest]
        else
          # Add to current chunk
          [{[mod_str | current_chunk], current_len + mod_len} | rest]
        end
      end)
      |> Enum.map(fn {chunk, _len} -> Enum.reverse(chunk) |> Enum.join("") end)
      |> Enum.reverse()

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    chunks
    |> Enum.with_index(1)
    |> Enum.each(fn {content, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(priv_dir, filename)

      yaml_content = "---\nskills:\n#{content}"

      case File.write(filepath, yaml_content) do
        :ok ->
          Logger.debug("Successfully wrote #{filename}")

        {:error, reason} ->
          Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
