# Serves the single-page React + Polaris app shell for all non-API routes.
# Client-side routing (React Router) takes over from there.
class AppController < ApplicationController
  def index
    render layout: false
  end
end
