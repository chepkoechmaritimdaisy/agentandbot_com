defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer that monitors application modules and generates SKILL.md documentation
  according to universal standards (YAML format, max 1024 characters per file).
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

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
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  defp update_skills do
    Logger.info("Running SkillTracker to update SKILL.md documentation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        generate_skill_docs(modules)
      :undefined ->
        Logger.error("SkillTracker: Could not get modules for governance_core")
    end
  end

  defp generate_skill_docs(modules) do
    # Extract module names as strings
    module_names = Enum.map(modules, &to_string/1)

    # Chunk the modules into multiple files to enforce the 1024 char limit per file
    chunks = chunk_modules(module_names, [], [], 0, 1024)

    # Write chunks to SKILL.md files in the source priv directory
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.with_index(chunks)
    |> Enum.each(fn {chunk_yaml, index} ->
      filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
      filepath = Path.join(priv_dir, filename)
      File.write!(filepath, chunk_yaml)
      Logger.debug("SkillTracker wrote #{filename}")
    end)
  end

  # Recursively chunks modules so that each generated YAML string is under max_chars
  defp chunk_modules([], current_chunk, chunks, _current_len, _max_chars) do
    if Enum.empty?(current_chunk) do
      Enum.reverse(chunks)
    else
      Enum.reverse([generate_yaml(Enum.reverse(current_chunk)) | chunks])
    end
  end

  defp chunk_modules([mod | rest], current_chunk, chunks, current_len, max_chars) do
    # Calculate the size of the YAML if we add this module
    test_chunk = [mod | current_chunk]
    test_yaml = generate_yaml(Enum.reverse(test_chunk))
    test_len = String.length(test_yaml)

    if test_len > max_chars and not Enum.empty?(current_chunk) do
      # Adding this module exceeds the limit, so finalize the current chunk
      finalized_yaml = generate_yaml(Enum.reverse(current_chunk))
      chunk_modules([mod | rest], [], [finalized_yaml | chunks], 0, max_chars)
    else
      # We can safely add this module to the current chunk
      chunk_modules(rest, test_chunk, chunks, test_len, max_chars)
    end
  end

  defp generate_yaml(module_list) do
    yaml_list =
      module_list
      |> Enum.map(fn m -> "  - name: #{m}" end)
      |> Enum.join("\\n")

    "skills:\\n" <> yaml_list <> "\\n"
  end
end
