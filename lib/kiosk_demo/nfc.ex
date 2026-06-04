defmodule KioskDemo.NFC do
  @moduledoc """
  Monitors a PN532 NFC reader on the I2C bus for passive tags.

  Tag enter/leave events are logged and broadcast on the `"nfc"`
  PubSub topic as `{:nfc, :in, uid}` / `{:nfc, :out, uid}` where
  `uid` is a lowercase hex string. Reader changes are broadcast as
  `{:nfc, :reader, :pn532 | :mock}`.

  If no reader is found at boot the process falls back to `LibNFC.Mock`
  so the rest of the system is unaffected. Tags can then be simulated
  from IEx with `LibNFC.Mock.put_target/0`.

  The PN532 + BCM2835 combination can wedge the I2C bus at the kernel
  level (a stuck transfer holds the adapter lock forever), so the open
  runs in a task with a timeout to never block boot.
  """
  use LibNFC.Presence

  require Logger

  @connstring "pn532_i2c:/dev/i2c-1"
  @open_retries 3
  @retry_delay_ms 500
  @open_timeout_ms 5_000

  @pubsub KioskDemo.PubSub
  @topic "nfc"

  @doc """
  The reader backing the monitor: `:pn532`, `:mock`, or `nil` before init.
  """
  @spec reader() :: :pn532 | :mock | nil
  def reader, do: :persistent_term.get({__MODULE__, :reader}, nil)

  @impl LibNFC.Presence
  def open_device(_client_state) do
    task = Task.async(fn -> try_open(@open_retries) end)

    case Task.yield(task, @open_timeout_ms) || Task.ignore(task) do
      {:ok, {:ok, device}} ->
        Logger.info("nfc: opened PN532 at #{@connstring} (libnfc #{LibNFC.version()})")
        set_reader(:pn532)
        {:ok, device}

      {:ok, :error} ->
        Logger.warning("nfc: no PN532 reader found at #{@connstring}, falling back to mock")
        open_mock()

      _timeout_or_exit ->
        Logger.warning("nfc: PN532 open timed out (I2C bus stuck?), falling back to mock")
        open_mock()
    end
  end

  @impl LibNFC.Presence
  def handle_target_in(target, _client_state) do
    uid = uid_hex(target["uid"])
    Logger.info("nfc: tag in: #{uid}")
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:nfc, :in, uid})
    {:ok, uid}
  end

  @impl LibNFC.Presence
  def handle_target_out(uid) do
    Logger.info("nfc: tag out: #{uid}")
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:nfc, :out, uid})
    {:ok, nil}
  end

  defp try_open(0), do: :error

  defp try_open(retries) do
    case LibNFC.open(@connstring) do
      {:ok, device} ->
        {:ok, device}

      :error ->
        Process.sleep(@retry_delay_ms)
        try_open(retries - 1)
    end
  end

  defp open_mock do
    set_reader(:mock)
    {:ok, _pid} = LibNFC.Mock.start_link()
    {:ok, :mock}
  end

  defp set_reader(reader) do
    :persistent_term.put({__MODULE__, :reader}, reader)
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:nfc, :reader, reader})
  end
end
