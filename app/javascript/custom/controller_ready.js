// Waiting for a Stimulus controller that lives in freshly injected HTML.
//
// Controllers are lazy-loaded (controllers/index.js): when markup naming a controller is added to
// the page, the loader imports that controller's module and only then connects it. Code that injects
// HTML and immediately interacts with it - clicks a tab, calls a method - can therefore run before
// the controller exists, and the click falls through to the bare element. Await this first.
//
// Resolves with the connected controller, or with null after `timeoutMs` (e.g. the element is gone
// or names a controller that doesn't exist), so callers degrade instead of hanging.
export function whenControllerConnected(application, element, identifier, timeoutMs = 5000) {
  return new Promise(resolve => {
    const started = performance.now()
    const check = () => {
      // Checked once per frame: connection happens a module fetch + a microtask after the import
      const controller = application.getControllerForElementAndIdentifier(element, identifier)
      if (controller || performance.now() - started > timeoutMs) return resolve(controller)
      requestAnimationFrame(check)
    }
    check()
  })
}
