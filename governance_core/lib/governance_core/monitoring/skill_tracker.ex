defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer that continuously generates SKILL.md documentation
  chunking the generated output dynamically to enforce a 1024 character limit.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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

  def perform_update do
    Logger.info("Updating SKILL.md...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # generate chunks based on actual yaml format length limit (1024)
        chunks = chunk_modules_by_yaml_length(modules, 1024)
        write_chunks(chunks)
      _ ->
        Logger.error("Failed to retrieve modules for SkillTracker.")
    end
  end

  defp chunk_modules_by_yaml_length(modules, limit) do
    {chunks, current_chunk, _current_length} =
      Enum.reduce(modules, {[], [], 0}, fn mod, {acc_chunks, curr_chunk, curr_len} ->
        mod_str = format_module(mod)
        mod_len = String.length(mod_str)

        if curr_len + mod_len > limit and curr_chunk != [] do
          {[Enum.reverse(curr_chunk) | acc_chunks], [mod_str], mod_len}
        else
          {acc_chunks, [mod_str | curr_chunk], curr_len + mod_len}
        end
      end)

    chunks = if current_chunk != [], do: [Enum.reverse(current_chunk) | chunks], else: chunks
    Enum.reverse(chunks)
  end

  defp format_module(mod) do
    # basic yaml list format representation
    "- module: #{inspect(mod)}\n"
  end

  defp write_chunks(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    chunks
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(priv_dir, filename)

      content = Enum.join(chunk)

      case File.write(filepath, content) do
        :ok ->
          Logger.info("SkillTracker successfully wrote #{filename}")
        {:error, reason} ->
          Logger.error("SkillTracker failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
