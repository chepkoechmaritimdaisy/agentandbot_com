defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates SKILL.md files dynamically to document available modules/tools.
  Enforces a 1024-character limit per file using YAML format.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_track()
    {:ok, state}
  end

  def handle_info(:track, state) do
    update_skills()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  def update_skills do
    Logger.info("Starting SkillTracker Update...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.sort()
        |> Enum.map(&to_string/1)
        |> generate_yaml_chunks()
        |> write_files()

      _ ->
        Logger.warning("Could not retrieve modules for SkillTracker.")
    end
  end

  defp generate_yaml_chunks(modules) do
    Enum.reduce(modules, {[], []}, fn module_name, {current_chunk, chunks} ->
      new_chunk = current_chunk ++ [module_name]
      yaml_content = build_yaml(new_chunk)

      if String.length(yaml_content) > 1024 do
        # Current chunk is full, start a new one with the current item
        {[module_name], chunks ++ [current_chunk]}
      else
        {new_chunk, chunks}
      end
    end)
    |> then(fn {last_chunk, chunks} ->
      if Enum.empty?(last_chunk) do
        chunks
      else
        chunks ++ [last_chunk]
      end
    end)
  end

  defp build_yaml(modules) do
    items = Enum.map(modules, fn m -> "  - #{m}" end) |> Enum.join("\n")
    "tools:\n#{items}\n"
  end

  defp write_files(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")

    # Ensure priv directory exists
    File.mkdir_p!(priv_dir)

    Enum.with_index(chunks)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
      file_path = Path.join(priv_dir, filename)
      yaml_content = build_yaml(chunk)

      case File.write(file_path, yaml_content) do
        :ok ->
          Logger.info("Successfully updated #{filename}")
        {:error, reason} ->
          Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
