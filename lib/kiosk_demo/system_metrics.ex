defmodule KioskDemo.SystemMetrics do
  @moduledoc """
  Periodic telemetry measurements for system-level metrics (CPU, memory).

  Emits `[:kiosk_demo, :system]` events that downstream telemetry metrics
  (and Mobius) consume.
  """

  @event_name [:kiosk_demo, :system]

  def event_name(), do: @event_name

  def measure() do
    measurements = %{
      cpu_util: cpu_util(),
      memory_used_mb: memory_used_mb(),
      load_avg_1: load_avg_1()
    }

    :telemetry.execute(@event_name, measurements, %{})
  end

  defp load_avg_1() do
    case safe_load_avg() do
      n when is_number(n) -> Float.round(n / 256, 2)
      _ -> 0.0
    end
  end

  defp safe_load_avg() do
    :cpu_sup.avg1()
  rescue
    _ -> 0
  catch
    _, _ -> 0
  end

  defp cpu_util() do
    case safe_cpu_util() do
      n when is_number(n) -> n * 1.0
      _ -> 0.0
    end
  end

  defp safe_cpu_util() do
    :cpu_sup.util()
  rescue
    _ -> 0.0
  catch
    _, _ -> 0.0
  end

  defp memory_used_mb() do
    bytes = :erlang.memory(:total)
    Float.round(bytes / 1_048_576, 2)
  end
end
