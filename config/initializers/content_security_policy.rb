Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :https, :data
    policy.object_src  :none
    policy.base_uri    :self
    policy.frame_ancestors :none
    policy.form_action :self
    policy.connect_src :self
    policy.script_src  :self
    # Polaris and a few small layout helpers use inline style attributes.
    policy.style_src   :self, :unsafe_inline
    # Allow Vite's development client to load assets and hot-reload changes.
    if Rails.env.development?
      vite_origin = "http://#{ViteRuby.config.host_with_port}"
      policy.connect_src *policy.connect_src, vite_origin, "ws://#{ViteRuby.config.host_with_port}"
      policy.script_src *policy.script_src, :unsafe_eval, vite_origin
    end
  end
end
