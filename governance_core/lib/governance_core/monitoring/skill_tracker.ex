defmodule GovernanceCore.Monitoring.SkillTracker do
  use GenServer
  require Logger

  @interval 5 * 60 * 1000
  @max_chars 1024

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_update()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:update, state) do
    Logger.info("SkillTracker updating SKILL.md...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        yaml_chunks = create_yaml_chunks(modules)
        write_files(yaml_chunks)

      _ ->
        Logger.error("SkillTracker failed to get modules")
    end

    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp create_yaml_chunks(modules) do
    # Chunking while enforcing @max_chars character limit dynamically per chunk
    {chunks, current_chunk, _current_len} =
      Enum.reduce(modules, {[], [], 0}, fn mod, {acc_chunks, acc_curr, acc_len} ->
        mod_str = "- #{inspect(mod)}\n"
        mod_len = String.length(mod_str)

        if acc_len + mod_len > @max_chars and acc_curr != [] do
          # The current chunk would exceed the limit, start a new one
          {[Enum.reverse(acc_curr) | acc_chunks], [mod_str], mod_len}
        else
          {acc_chunks, [mod_str | acc_curr], acc_len + mod_len}
        end
      end)

    chunks =
      if current_chunk != [] do
        [Enum.reverse(current_chunk) | chunks]
      else
        chunks
      end

    Enum.reverse(chunks)
    |> Enum.map(fn chunk ->
      "modules:\n" <> Enum.join(chunk, "")
    end)
  end

  defp write_files(yaml_chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.with_index(yaml_chunks, 1)
    |> Enum.each(fn {yaml_content, index} ->
      filename =
        if index == 1 do
          "SKILL.md"
        else
          "SKILL_#{index}.md"
        end

      filepath = Path.join(priv_dir, filename)

      case File.write(filepath, yaml_content) do
        :ok ->
          Logger.info("SkillTracker successfully wrote #{filename}")

        {:error, reason} ->
          Logger.error("SkillTracker failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
