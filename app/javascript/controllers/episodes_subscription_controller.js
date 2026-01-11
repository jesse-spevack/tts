import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Subscribes to EpisodesChannel for real-time episode status updates.
// On subscription, the server broadcasts current state of any in-progress
// episodes to handle the race condition where status changes may occur
// before the WebSocket connection is established.
export default class extends Controller {
  static values = {
    podcastId: String
  }

  connect() {
    this.subscription = createConsumer().subscriptions.create(
      { channel: "EpisodesChannel", podcast_id: this.podcastIdValue },
      {
        received: this.handleReceived.bind(this)
      }
    )
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  handleReceived(data) {
    // Turbo Stream messages come as HTML strings
    Turbo.renderStreamMessage(data)
  }
}
