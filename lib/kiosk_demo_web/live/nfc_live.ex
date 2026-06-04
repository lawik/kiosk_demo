defmodule KioskDemoWeb.NFCLive do
  @moduledoc """
  Live demo screen for the PN532 NFC reader.

  Shows the current tag in range and a log of recent tag enter/leave
  events, fed by the `"nfc"` PubSub topic from `KioskDemo.NFC`.
  """
  use KioskDemoWeb, :live_view

  @topic "nfc"
  @max_events 10

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(KioskDemo.PubSub, @topic)
    end

    {:ok, name} = :inet.gethostname()

    socket =
      socket
      |> assign(:hostname, to_string(name))
      |> assign(:reader, reader_status())
      |> assign(:current_tag, nil)
      |> assign(:events, [])

    {:ok, socket}
  end

  def handle_info({:nfc, :reader, reader}, socket) do
    {:noreply, assign(socket, :reader, reader)}
  end

  def handle_info({:nfc, :in, uid}, socket) do
    socket =
      socket
      |> assign(:current_tag, uid)
      |> add_event(:in, uid)

    {:noreply, socket}
  end

  def handle_info({:nfc, :out, uid}, socket) do
    socket =
      socket
      |> assign(:current_tag, nil)
      |> add_event(:out, uid)

    {:noreply, socket}
  end

  defp add_event(socket, kind, uid) do
    event = %{kind: kind, uid: uid, at: NaiveDateTime.local_now()}
    update(socket, :events, &Enum.take([event | &1], @max_events))
  end

  defp reader_status do
    if Code.ensure_loaded?(KioskDemo.NFC) and function_exported?(KioskDemo.NFC, :reader, 0) do
      KioskDemo.NFC.reader()
    end
  end

  defp format_uid(uid) do
    uid
    |> String.upcase()
    |> String.codepoints()
    |> Enum.chunk_every(2)
    |> Enum.map_join(":", &Enum.join/1)
  end

  def render(assigns) do
    ~H"""
    <style>
      .kiosk-hero-dark {
        position: relative;
        background-color: #000;
        overflow: hidden;
        isolation: isolate;
      }

      .kiosk-body-light {
        position: relative;
        background-color: #f8fafc;
        overflow: hidden;
        isolation: isolate;
      }

      .kiosk-body-light::before {
        content: "";
        position: absolute;
        inset: -20%;
        z-index: -1;
        pointer-events: none;
        background-image:
          radial-gradient(ellipse 35% 35% at 85% 75%, oklch(75% 0.14 245 / 0.45), transparent 70%),
          radial-gradient(ellipse 28% 32% at 90% 55%, oklch(83% 0.10 210 / 0.30), transparent 60%),
          radial-gradient(ellipse 25% 22% at 15% 30%, oklch(80% 0.09 290 / 0.30), transparent 60%);
      }

      .kiosk-title {
        font-family: "Poppins", "Helvetica Neue", "Segoe UI", system-ui, -apple-system, sans-serif;
        font-weight: 100;
        font-size: clamp(2.25rem, 4.5vw, 3.75rem);
        line-height: 1.1;
      }

      .tag-uid {
        font-size: clamp(1.75rem, 4vw, 3.25rem);
      }

      @keyframes tag-pulse {
        0%, 100% { box-shadow: 0 0 0 0 oklch(72% 0.19 150 / 0.5); }
        50% { box-shadow: 0 0 0 24px oklch(72% 0.19 150 / 0); }
      }

      .tag-present {
        animation: tag-pulse 2s ease-out infinite;
      }
    </style>

    <div class="relative min-h-screen flex flex-col">
      <section class="kiosk-hero-dark">
        <div class="px-4 py-10 sm:px-6 lg:px-8 xl:px-28">
          <div class="mx-auto max-w-6xl flex items-center justify-between gap-4">
            <h1 class="kiosk-title text-slate-100">NFC Reader</h1>
            <span
              :if={@reader == :pn532}
              class="inline-flex items-center gap-2 rounded-full bg-green-500/15 px-4 py-2 text-sm font-semibold text-green-400"
            >
              <span class="size-2 rounded-full bg-green-400"></span> PN532 on I2C
            </span>
            <span
              :if={@reader == :mock}
              class="inline-flex items-center gap-2 rounded-full bg-amber-500/15 px-4 py-2 text-sm font-semibold text-amber-400"
            >
              <span class="size-2 rounded-full bg-amber-400"></span> Mock reader
            </span>
            <span
              :if={is_nil(@reader)}
              class="inline-flex items-center gap-2 rounded-full bg-slate-500/15 px-4 py-2 text-sm font-semibold text-slate-400"
            >
              <span class="size-2 rounded-full bg-slate-400"></span> No reader
            </span>
          </div>
        </div>
      </section>

      <div class="kiosk-body-light flex-1 px-4 py-8 sm:px-6 lg:px-8 xl:px-28">
        <div class="mx-auto max-w-6xl space-y-8">
          <div
            :if={@current_tag}
            class="tag-present rounded-2xl bg-white border-2 border-green-400 px-8 py-12 text-center shadow-lg"
          >
            <p class="text-sm font-semibold uppercase tracking-widest text-green-600 mb-4">
              Tag in range
            </p>
            <p class="tag-uid font-mono font-bold text-slate-900 break-all">
              {format_uid(@current_tag)}
            </p>
          </div>

          <div
            :if={is_nil(@current_tag)}
            class="rounded-2xl bg-white/60 border-2 border-dashed border-slate-300 px-8 py-12 text-center"
          >
            <.icon name="hero-signal" class="size-12 text-slate-400 mb-4" />
            <p class="tag-uid font-light text-slate-400">Tap a tag on the reader</p>
          </div>

          <div :if={@events != []}>
            <p class="text-sm font-semibold uppercase tracking-widest text-slate-500 mb-3">
              Recent events
            </p>
            <table class="w-full text-sm bg-white/70 rounded-xl overflow-hidden">
              <tbody class="divide-y divide-slate-200">
                <tr :for={event <- @events}>
                  <td class="py-2 px-4 w-28 font-mono text-xs text-slate-500">
                    {Calendar.strftime(event.at, "%H:%M:%S")}
                  </td>
                  <td class="py-2 px-4 w-20">
                    <span
                      :if={event.kind == :in}
                      class="inline-flex rounded-full bg-green-100 px-2 py-0.5 text-xs font-semibold text-green-700"
                    >
                      in
                    </span>
                    <span
                      :if={event.kind == :out}
                      class="inline-flex rounded-full bg-slate-200 px-2 py-0.5 text-xs font-semibold text-slate-600"
                    >
                      out
                    </span>
                  </td>
                  <td class="py-2 px-4 font-mono text-slate-900">{format_uid(event.uid)}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <p :if={@reader == :mock} class="text-center text-sm text-slate-500">
            No PN532 found — simulate tags from IEx with
            <code class="bg-slate-200 px-2 py-1 rounded font-mono text-xs">
              LibNFC.Mock.put_target()
            </code>
            and
            <code class="bg-slate-200 px-2 py-1 rounded font-mono text-xs">
              LibNFC.Mock.clear_target()
            </code>
          </p>

          <p class="text-center text-sm text-slate-500">
            <code class="font-mono">ssh kiosk@{@hostname}.local</code>
            · password <span class="font-semibold">kiosk</span>
            · <a href="/home" class="text-blue-600 hover:text-blue-700">system info</a>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
