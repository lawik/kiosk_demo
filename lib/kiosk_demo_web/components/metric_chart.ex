defmodule KioskDemoWeb.Components.MetricChart do
  @moduledoc """
  Inline SVG line chart that doubles as a horizon-style color transition
  between two page sections.

  The SVG is divided by the primary metric polyline: the area above is
  filled with `:dark_color` (intended to match the section above), the
  area below is filled with `:light_color` (intended to match the
  section below).

  `:overlays` allows additional metric series to render as opaque ghost
  horizons behind the primary one. Each overlay is an opaque solid-color
  fill — the layered fills produce a "bright-to-dark" stacked-horizon
  look.

  Hovering any region with a `:label` reveals a monospace tooltip at the
  top of the chart.
  """

  use Phoenix.Component

  attr :id, :string, required: true
  attr :dark_color, :string, default: "transparent"
  attr :light_color, :string, default: "#f8fafc"
  attr :width, :integer, default: 1000
  attr :height, :integer, default: 80
  attr :transition_ms, :integer, default: 2000

  attr :series, :list,
    required: true,
    doc: "primary series; list of %{timestamp: ts, value: v}"

  attr :overlays, :list,
    default: [],
    doc: """
    list of overlay maps:
      %{
        series: [%{timestamp: ts, value: v}],
        fill: "#334155",        # opaque fill color (optional)
        height_scale: 1.5,      # virtual height multiplier (optional)
        min: nil, max: nil,     # explicit bounds (optional)
        label: "memory"         # hover tooltip text (optional)
      }
    """

  attr :primary_label, :string, default: nil

  attr :min, :any, default: nil
  attr :max, :any, default: nil
  attr :height_scale, :float, default: 1.0

  def line_chart(assigns) do
    assigns =
      assigns
      |> assign(:geometry, build_geometry(assigns, assigns.series))
      |> assign(
        :overlay_data,
        assigns.overlays
        |> Enum.map(fn ov ->
          %{
            geometry:
              build_geometry(
                %{width: assigns.width, height: assigns.height},
                ov[:series] || [],
                ov
              ),
            fill: ov[:fill] || "#1f2937",
            label: ov[:label]
          }
        end)
      )

    labels =
      [assigns.primary_label | Enum.map(assigns.overlay_data, & &1.label)]
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    assigns = assign(assigns, :labels, labels)

    ~H"""
    <div class={"chart-wrap chart-wrap-#{@id}"}>
      <svg
        id={@id}
        viewBox={"0 0 #{@width} #{@height}"}
        preserveAspectRatio="none"
        class="w-full h-20 block"
        aria-hidden="true"
      >
        <rect id={"#{@id}-bg"} x="0" y="0" width={@width} height={@height} fill={@dark_color} />

        <%= for ov <- @overlay_data, ov.geometry.area do %>
          <path
            class={if ov.label, do: "chart-region", else: nil}
            data-metric={ov.label}
            d={ov.geometry.area}
            fill={ov.fill}
            style={"transition: d #{@transition_ms}ms linear; will-change: d;"}
          />
        <% end %>

        <%= if @geometry.area do %>
          <path
            id={"#{@id}-area"}
            class={if @primary_label, do: "chart-region", else: nil}
            data-metric={@primary_label}
            d={@geometry.area}
            fill={@light_color}
            style={"transition: d #{@transition_ms}ms linear; will-change: d;"}
          />
        <% else %>
          <rect
            id={"#{@id}-area-placeholder"}
            x="0"
            y={@height - 1}
            width={@width}
            height="1"
            fill={@light_color}
          />
        <% end %>
      </svg>

      <span :for={label <- @labels} class="chart-tooltip" data-metric={label}>{label}</span>

      <style>
        .chart-wrap { position: relative; }
        .chart-region { cursor: crosshair; }
        .chart-tooltip {
          position: absolute;
          top: 6px;
          left: 50%;
          transform: translateX(-50%);
          font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
          font-size: 11px;
          color: #f1f5f9;
          visibility: hidden;
          opacity: 0;
          pointer-events: none;
          white-space: nowrap;
          transition: opacity 120ms ease-out;
          z-index: 2;
        }
        <%= for label <- @labels do %>
        .chart-wrap-<%= @id %>:has(.chart-region[data-metric="<%= label %>"]:hover) .chart-tooltip[data-metric="<%= label %>"] { visibility: visible; opacity: 1; }
        <% end %>
      </style>
    </div>
    """
  end

  defp build_geometry(%{width: w, height: h} = ctx, series, bounds_source \\ %{}) do
    values = Enum.map(series, & &1.value)

    case values do
      [] ->
        %{area: nil}

      _ ->
        {min_v, max_v} =
          bounds(values, bounds_source[:min] || ctx[:min], bounds_source[:max] || ctx[:max])

        span = max(max_v - min_v, 1.0e-6)
        scale = bounds_source[:height_scale] || ctx[:height_scale] || 1.0
        effective_h = h * scale
        top_margin = 2.0
        count = length(values)

        points =
          values
          |> Enum.with_index()
          |> Enum.map(fn {v, i} ->
            x = if count == 1, do: w / 2, else: i * w / (count - 1)
            y_raw = h - (v - min_v) / span * effective_h
            y = clamp(y_raw, top_margin, h)
            {x, y}
          end)

        %{area: points_to_smooth_area(points, h)}
    end
  end

  defp bounds(values, min_override, max_override) do
    {min_v, max_v} = Enum.min_max(values)
    min_v = if is_number(min_override), do: min_override, else: floor_to_step(min_v)
    max_v = if is_number(max_override), do: max_override, else: ceil_to_step(max_v)
    max_v = if max_v <= min_v, do: min_v + 1.0, else: max_v
    {min_v * 1.0, max_v * 1.0}
  end

  defp floor_to_step(v), do: Float.floor(v * 1.0)
  defp ceil_to_step(v), do: Float.ceil(v * 1.0)

  defp clamp(v, lo, _hi) when v < lo, do: lo
  defp clamp(v, _lo, hi) when v > hi, do: hi
  defp clamp(v, _lo, _hi), do: v

  defp points_to_smooth_path([]), do: nil
  defp points_to_smooth_path([{x, y}]), do: "M #{fmt(x)} #{fmt(y)}"

  defp points_to_smooth_path([{x0, y0}, {x1, y1}]) do
    "M #{fmt(x0)} #{fmt(y0)} L #{fmt(x1)} #{fmt(y1)}"
  end

  defp points_to_smooth_path(points) do
    arr = List.to_tuple(points)
    count = tuple_size(arr)
    {x0, y0} = elem(arr, 0)

    segments =
      for i <- 1..(count - 1) do
        {x1, y1} = elem(arr, i - 1)
        {x2, y2} = elem(arr, i)
        {p0x, p0y} = elem(arr, max(i - 2, 0))
        {p3x, p3y} = elem(arr, min(i + 1, count - 1))

        cp1x = x1 + (x2 - p0x) / 6
        cp1y = y1 + (y2 - p0y) / 6
        cp2x = x2 - (p3x - x1) / 6
        cp2y = y2 - (p3y - y1) / 6

        "C #{fmt(cp1x)} #{fmt(cp1y)} #{fmt(cp2x)} #{fmt(cp2y)} #{fmt(x2)} #{fmt(y2)}"
      end

    "M #{fmt(x0)} #{fmt(y0)} " <> Enum.join(segments, " ")
  end

  defp points_to_smooth_area([], _h), do: nil

  defp points_to_smooth_area(points, h) do
    {first_x, _} = hd(points)
    {last_x, _} = List.last(points)
    line = points_to_smooth_path(points)
    "#{line} L #{fmt(last_x)} #{fmt(h)} L #{fmt(first_x)} #{fmt(h)} Z"
  end

  defp fmt(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 1)
  defp fmt(v), do: to_string(v)
end
