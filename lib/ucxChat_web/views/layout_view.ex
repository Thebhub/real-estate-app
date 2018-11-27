defmodule UcxChatWeb.LayoutView do
  use UcxChatWeb, :view

  def audio_files do
    ~w(chime beep chelle ding droplet highbell seasons door)
    |> Enum.map(&({&1, "/sounds/#{&1}.mp3"}))
  end

  def site_title do
    Settings.site_name()
  end
end
