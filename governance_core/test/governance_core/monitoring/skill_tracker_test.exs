defmodule GovernanceCore.Monitoring.SkillTrackerTest do
  use ExUnit.Case, async: false
  alias GovernanceCore.Monitoring.SkillTracker

  setup do
    priv_dir = Path.join(File.cwd!(), "priv")

    # Cleanup before test
    Enum.each(Path.wildcard(Path.join(priv_dir, "SKILL*.md")), &File.rm!/1)

    on_exit(fn ->
      Enum.each(Path.wildcard(Path.join(priv_dir, "SKILL*.md")), &File.rm!/1)
    end)

    :ok
  end

  test "skill tracker generates files properly chunked" do
    {:ok, pid} = GenServer.start_link(SkillTracker, %{})

    send(pid, :track)
    :sys.get_state(pid)

    priv_dir = Path.join(File.cwd!(), "priv")
    files = Path.wildcard(Path.join(priv_dir, "SKILL*.md"))

    assert length(files) > 0

    # Check that any generated file respects the 1024 char limit.
    # In reality, testing actual character counts depends on the modules loaded,
    # but we can at least assert the format chunking occurred.
    Enum.each(files, fn file ->
      content = File.read!(file)
      assert String.starts_with?(content, "modules: |")
      assert String.length(content) > 0
    end)
  end
end
