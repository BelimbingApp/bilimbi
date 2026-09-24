// Loaded before every test file (`npm test` passes it to `--import`), so a
// hook module that touches `document` at import time -- modal.js arms a
// listener there -- finds a real one.
//
// happy-dom is a browser DOM in Node: real elements, events, focus,
// MutationObserver and timers. It is not a browser. It draws nothing, has no
// top layer, and does not blur an element that becomes hidden. A test that
// depends on one of those says so where it does.
import {GlobalRegistrator} from "@happy-dom/global-registrator"

GlobalRegistrator.register({url: "http://localhost/"})
