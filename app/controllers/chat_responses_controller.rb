class ChatResponsesController < ApplicationController
  include ActionController::Live

  def show
    # Set the content type for SSE
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Last-Modified'] = Time.now.httpdate

    # Initialize SSE stream
    sse = SSE.new(response.stream, event: "message")

    # Check for missing prompt parameter
    unless params[:prompt].present?
      sse.write({ message: "No prompt provided" })
      sse.close
      return
    end

    # Initialize OpenAI client
    client = OpenAI::Client.new(access_token: ENV["OPENAI_ACCESS_TOKEN"])

    begin
      # Call the OpenAI API and stream the response
      client.chat(
        parameters: {
          model: "gpt-3.5-turbo",
          messages: [{ role: "user", content: params[:prompt] }],
          stream: proc do |chunk|
            # Log the raw chunk for debugging
            Rails.logger.debug("Received chunk: #{chunk.inspect}")

            # Extract content from the chunk
            content = chunk.dig("choices", 0, "delta", "content")

            # If content is nil, continue the loop, don't terminate
            if content.nil?
              next
            end

            # Log the content that is sent to the client
            Rails.logger.debug("Sending content to client: #{content}")

            # Send the content to the client as an SSE event
            sse.write({ message: content })
          end
        }
      )
    rescue => e
      # In case of error, send a generic error message to the client
      sse.write({ message: "Error occurred: #{e.message}" })
    ensure
      # Ensure the SSE stream is closed
      sse.close
    end
  end
end
