defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer to dynamically track application modules and format them into SKILL.md.
  Ensures no SKILL.md file exceeds the universal 1024 character limit by chunking correctly.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update_skills, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  def update_skills do
    Logger.info("Starting SKILL.md standardization...")

    {:ok, modules} = :application.get_key(:governance_core, :modules)

    # Format to a basic structure for YAML representation
    formatted_modules = Enum.map(modules, &to_string/1)

    chunk_and_write(formatted_modules, 1)
  end

  defp chunk_and_write([], _index), do: :ok
  defp chunk_and_write(modules, index) do
    {chunk, remaining} = take_until_limit(modules, [], 0, 1024)

    filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
    file_path = Path.join(File.cwd!(), "priv/#{filename}")

    yaml_content = generate_yaml(chunk)

    # Ensure priv directory exists
    File.mkdir_p!(Path.dirname(file_path))

    File.write!(file_path, yaml_content)
    Logger.info("Written #{filename} with #{length(chunk)} modules")

    chunk_and_write(remaining, index + 1)
  end

  defp take_until_limit([], acc, _current_length, _limit) do
    {Enum.reverse(acc), []}
  end
  defp take_until_limit([mod | rest], acc, current_length, limit) do
    # Calculate the length that this module would add if formatted as YAML item
    # Example format: "\n  - #{mod}" -> length is 5 + length(mod)
    added_length = 5 + String.length(mod)

    # Also account for header on first item
    header_length = if current_length == 0, do: String.length("skills:\n"), else: 0

    if current_length + added_length + header_length > limit and length(acc) > 0 do
      {Enum.reverse(acc), [mod | rest]}
    else
      take_until_limit(rest, [mod | acc], current_length + added_length + header_length, limit)
    end
  end

  defp generate_yaml(modules) do
    "skills:\n" <> Enum.map_join(modules, "\n", fn mod -> "  - #{mod}" end)
  end
end
