defmodule UcxChatWeb.ServiceHelpers do
  # use UcxChatWeb, :service
  alias UcxChat.{
    Repo, Channel, User, Subscription, MessageService, User, UserRole
  }

  require UcxChat.SharedView
  use UcxChat.Gettext

  import Ecto.Query

  @default_user_preload [:account, :roles]

  def default_user_preloads, do: @default_user_preload

  def get_user!(%Phoenix.Socket{assigns: assigns}) do
    get_user!(assigns[:user_id])
  end

  def get_user!(id) do
    Repo.one!(from u in User, where: u.id == ^id, preload: ^@default_user_preload)
  end

  def get_user(%Phoenix.Socket{assigns: assigns}) do
    get_user(assigns[:user_id])
  end

  def get_user(id, _opts \\ []) do
    Repo.one(from u in User, where: u.id == ^id, preload: ^@default_user_preload)
  end

  def get!(model, id, opts \\ []) do
    preload = opts[:preload] || []
    model
    |> where([c], c.id == ^id)
    |> preload(^preload)
    |> Repo.one!
  end

  def get(model, id, opts \\ []) do
    preload = opts[:preload] || []
    model
    |> where([c], c.id == ^id)
    |> preload(^preload)
    |> Repo.one
  end

  def get_by!(model, field, value, opts \\ []) do
    model
    |> get_by_q(field, value, opts)
    |> Repo.one!
  end

  def get_by(model, field, value, opts \\ []) do
    model
    |> get_by_q(field, value, opts)
    |> Repo.one
  end

  def get_channel(channel_id, preload \\ []) do
    Channel
    |> where([c], c.id == ^channel_id)
    |> preload(^preload)
    |> Repo.one!
  end

  def get_all_by(model, field, value, opts \\ []) do
    model
    |> get_by_q(field, value, opts)
    |> Repo.all
  end

  defp get_by_q(model, field, value, opts) do
    preload = opts[:preload] || []
    model
    |> where([c], field(c, ^field) == ^value)
    |> preload(^preload)
  end

  def get_channel_user(channel_id, user_id, opts \\ []) do
    preload = opts[:preload] || []

    Subscription
    |> where([c], c.user_id == ^user_id and c.channel_id == ^channel_id)
    |> preload(^preload)
    |> Repo.one!
  end

  def get_user_by_name(username, opts \\ [])
  def get_user_by_name(nil, _), do: nil
  def get_user_by_name(username, opts) do
    preload = if opts[:preload] == false, do: [], else: @default_user_preload
    User
    |> where([c], c.username == ^username)
    |> preload(^preload)
    |> Repo.one!
  end

  def count(query) do
    query |> select([m], count(m.id)) |> Repo.one
  end

  def last_page(query, page_size \\ 75) do
    count = count(query)
    offset = case count - page_size do
      offset when offset >= 0 -> offset
      _ -> 0
    end
    query |> offset(^offset) |> limit(^page_size)
  end

  @dt_re ~r/(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\.(\d+)/

  def get_timestamp() do
    @dt_re
    |> Regex.run(DateTime.utc_now() |> to_string)
    |> tl
    |> to_string
    # |> String.to_integer
  end

  def format_date(%NaiveDateTime{} = dt) do
    {{yr, mo, day}, _} = NaiveDateTime.to_erl(dt)
    month(mo) <> " " <> to_string(day) <> ", " <> to_string(yr)
  end
  def format_date(%DateTime{} = dt), do: dt |> DateTime.to_naive |> format_date

  def format_time(%NaiveDateTime{} = dt) do
    {_, {hr, min, _sec}} = NaiveDateTime.to_erl(dt)
    min = to_string(min) |> String.pad_leading(2, "0")
    {hr, meridan} =
      case hr do
        hr when hr < 12 -> {hr, ~g" AM"}
        hr when hr == 12 -> {hr, ~g" PM"}
        hr -> {hr - 12, ~g" PM"}
      end
    to_string(hr) <> ":" <> min <> meridan
  end
  def format_time(%DateTime{} = dt), do: dt |> DateTime.to_naive |> format_time

  def format_date_time(%NaiveDateTime{} = dt) do
    format_date(dt) <> " " <> format_time(dt)
  end
  def format_date_time(%DateTime{} = dt), do: dt |> DateTime.to_naive |> format_date_time

  def format_javascript_errors([]), do: %{}
  def format_javascript_errors(errors) do
    errors
    |> Enum.map(fn {k, {msg, opts}} ->
      error = if count = opts[:count] do
        Gettext.dngettext(UcxChat.Gettext, "errors", msg, msg, count, opts)
      else
        Gettext.dgettext(UcxChat.Gettext, "errors", msg, opts)
      end
      {k, error}
    end)
    |> Enum.into(%{})
  end

  def month(1), do: ~g"January"
  def month(2), do: ~g"February"
  def month(3), do: ~g"March"
  def month(4), do: ~g"April"
  def month(5), do: ~g"May"
  def month(6), do: ~g"June"
  def month(7), do: ~g"July"
  def month(8), do: ~g"August"
  def month(9), do: ~g"September"
  def month(10), do: ~g"October"
  def month(11), do: ~g"November"
  def month(12), do: ~g"December"

  def response_message(channel_id, body) do
    # body = UcxChat.MessageView.render("message_response_body.html", message: message)
    # |> Phoenix.HTML.safe_to_string

    bot_id = get_bot_id()
    message = MessageService.create_message(body, bot_id, channel_id,
      %{
        type: "p",
        system: true,
        sequential: false,
      })

    html = MessageService.render_message(message)
    # message =
    #   message
    #   |> Enum.filter(&elem(&1, 0) == :text)
    #   |> Enum.join("")

    %{html: html, message: message.body}
  end
  def get_bot_id do
    Repo.one from u in User,
    join: r in UserRole, on: r.user_id == u.id,
    where: r.role ==  "bot",
    select: u.id,
    limit: 1
    # User
    # # |> where([m], m.type == "b")
    # |> select([m], m.id)
    # |> limit(1)
    # |> Repo.one
  end

  def render(view, templ, opts \\ []) do
    templ
    |> view.render(opts)
    |> safe_to_string
  end

  @doc """
  Convert form submission params form channel into params for changesets.

  ## Examples

        iex> params =  [%{"name" => "_utf8", "value" => "✓"},
        ...> %{"name" => "account[language]", "value" => "en"},
        ...> %{"name" => "account[desktop]", "value" => ""},
        ...> %{"name" => "account[alert]", "value" => "1"}]
        iex> UcxChat.ServiceHelpers.normalize_form_params(params)
        %{"_utf8" => "✓", "account" => %{"language" => "en", "alert" => "1"}}
  """
  def normalize_form_params(params) do
    Enum.reduce params, %{}, fn
      %{"name" => _field, "value" => ""}, acc ->
        acc
      %{"name" => field, "value" => value}, acc ->
        parse_name(field)
        |> Enum.reduce(value, fn key, acc -> Map.put(%{}, key, acc) end)
        |> UcxChat.Utils.deep_merge(acc)
    end
  end

  defp parse_name(string), do: parse_name(string, "", [])

  defp parse_name("", "", acc), do: acc
  defp parse_name("", buff, acc), do: [buff|acc]
  defp parse_name("[" <> tail, "", acc), do: parse_name(tail, "", acc)
  defp parse_name("[" <> tail, buff, acc), do: parse_name(tail, "", [buff|acc])
  defp parse_name("]" <> tail, buff, acc), do: parse_name(tail, "", [buff|acc])
  defp parse_name(<<ch::8>> <> tail, buff, acc), do: parse_name(tail, buff <> <<ch::8>>, acc)

  def broadcast_message(body, user_id, channel_id) do
    channel = get! Channel, channel_id
    broadcast_message(body, channel.name, user_id, channel_id)
  end

  def broadcast_message(body, room, user_id, channel_id, opts \\ []) do
    UcxChat.TypingAgent.stop_typing(channel_id, user_id)
    MessageService.update_typing(channel_id, room)
    {message, html} = MessageService.create_and_render(body, user_id, channel_id, opts)
    MessageService.broadcast_message(message.id, room, user_id, html)
  end

  def show_sweet_dialog(socket, opts) do
    header = if opts[:confirm], do: opts[:header] || ~g"Are you sure?"
    opts = Map.put(opts, :header, header)

    html = UcxChat.MasterView.render("sweet.html", opts: Map.put(opts, :show, true))
    |> safe_to_string
    Phoenix.Channel.push socket, "sweet:open", %{html: html}
  end

  def strip_tags(html) do
    String.replace html, ~r/<.*?>/, ""
  end
  # def hide_sweet_dialog(socket) do

  # end
  def safe_to_string(safe) do
    safe
    |> Phoenix.HTML.safe_to_string
    |> String.replace(~r/\n\s*/, " ")
  end

end
