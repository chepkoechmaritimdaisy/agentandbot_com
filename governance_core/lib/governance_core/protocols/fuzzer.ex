defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes ClawSpeak and UMP protocols.
  """
  use GenServer
  require Logger

  alias GovernanceCore.Protocols.{ClawSpeak, UMP}

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzz do
    Logger.info("Starting ClawSpeak and UMP Fuzzing...")

    try do
      fuzz_clawspeak()
    rescue
      e -> Logger.error("Fuzzer caught exception in ClawSpeak: #{inspect(e)}")
    catch
      type, value -> Logger.error("Fuzzer caught throw/exit in ClawSpeak: #{inspect({type, value})}")
    end

    try do
      fuzz_ump()
    rescue
      e -> Logger.error("Fuzzer caught exception in UMP: #{inspect(e)}")
    catch
      type, value -> Logger.error("Fuzzer caught throw/exit in UMP: #{inspect({type, value})}")
    end

    Logger.info("Fuzzing cycle completed.")
  end

  defp fuzz_clawspeak do
    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(fn binary ->
      try do
        ClawSpeak.decode(binary)
      rescue
        e -> Logger.error("Fuzzer caught exception in ClawSpeak.decode: #{inspect(e)}")
      catch
        type, value -> Logger.error("Fuzzer caught throw/exit in ClawSpeak.decode: #{inspect({type, value})}")
      end
    end)
  end

  defp fuzz_ump do
    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(fn binary ->
      try do
        UMP.parse(binary)
      rescue
        e -> Logger.error("Fuzzer caught exception in UMP.parse: #{inspect(e)}")
      catch
        type, value -> Logger.error("Fuzzer caught throw/exit in UMP.parse: #{inspect({type, value})}")
      end
    end)
  end
end
