defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically updates SKILL.md documentation based on discovered modules,
  adhering to evrensel standartlara (universal standards) like 1024 char limits per file.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000
  @char_limit 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_update()
    {:ok, state}
  end

  @impl true
  def handle_info(:update_skills, state) do
    update_skill_docs()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  def update_skill_docs do
    Logger.info("SkillTracker: Updating SKILL.md documentation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Find some interesting modules
        skill_modules =
          Enum.filter(modules, fn mod ->
            mod_str = to_string(mod)
            String.starts_with?(mod_str, "Elixir.GovernanceCore.")
          end)

        generate_skill_files(skill_modules)

      :undefined ->
        Logger.warning("SkillTracker: Could not get modules from application.")
    end
  end

  defp generate_skill_files(modules) do
    # Generate YAML representation for each module
    yaml_items =
      Enum.map(modules, fn mod ->
        """
        - module: #{inspect(mod)}
          type: tool
          status: active
        """
      end)

    # Chunk items based on cumulative string length + header length
    header = "---\nversion: 1.0\nskills:\n"

    {chunks, _} =
      Enum.reduce(yaml_items, {[], {[], String.length(header)}}, fn item, {acc_chunks, {curr_chunk, curr_len}} ->
        item_len = String.length(item)

        if curr_len + item_len > @char_limit && curr_chunk != [] do
          # Start a new chunk
          new_chunk = [item]
          new_len = String.length(header) + item_len
          {acc_chunks ++ [Enum.reverse(curr_chunk)], {new_chunk, new_len}}
        else
          # Add to current chunk
          {acc_chunks, {[item | curr_chunk], curr_len + item_len}}
        end
      end)

    # Process the last chunk
    final_chunks =
      case chunks do
        [] -> [] # Handled later
        _ -> chunks
      end

    # Handle the remaining items in the accumulator if any
    final_chunks =
      # we need to extract the accumulator from the reduce
      case Enum.reduce(yaml_items, {[], {[], String.length(header)}}, fn item, {acc_chunks, {curr_chunk, curr_len}} ->
             item_len = String.length(item)
             if curr_len + item_len > @char_limit && curr_chunk != [] do
               {acc_chunks ++ [Enum.reverse(curr_chunk)], {[item], String.length(header) + item_len}}
             else
               {acc_chunks, {[item | curr_chunk], curr_len + item_len}}
             end
           end) do
        {acc, {[], _}} -> acc
        {acc, {curr_chunk, _}} -> acc ++ [Enum.reverse(curr_chunk)]
      end

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.with_index(final_chunks, 1)
    |> Enum.each(fn {chunk, index} ->
      filename =
        if index == 1 do
          "SKILL.md"
        else
          "SKILL_#{index}.md"
        end

      file_path = Path.join(priv_dir, filename)

      content = header <> Enum.join(chunk, "")

      case File.write(file_path, content) do
        :ok ->
          Logger.info("SkillTracker: Successfully wrote #{filename}")

        {:error, reason} ->
          Logger.error("SkillTracker: Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
