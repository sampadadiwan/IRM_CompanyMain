import {Turbo} from '@hotwired/turbo-rails'

const adapter = Turbo.navigator.delegate.adapter;

document.addEventListener('turbo:before-fetch-request', function(event){
  const target = event.target;
  if (!(target instanceof HTMLElement)) return;

  if (target.getAttribute('data-turbo-action') === 'advance') {
    adapter.formSubmissionStarted(this)
  }
});

document.addEventListener('turbo:before-fetch-response', function(event) {
  adapter.formSubmissionFinished(this);
});