#ifndef RUNNER_STARTUP_WATCHDOG_H_
#define RUNNER_STARTUP_WATCHDOG_H_

// גלאי תקיעות של ה-thread הראשי בעלייה. ב-Windows ה-UI isolate של Dart רץ על
// ה-thread הזה, ולכן קוד נייטיב סינכרוני חוסם גם את הפריימים וגם את הטיימרים.
namespace startup_watchdog {

// מתחיל את הניטור. יש לקרוא מה-thread הראשי לפני לולאת ההודעות.
void Start();

// עוצר את הניטור (בחשיפת החלון או ביציאה). בטוח לקריאה חוזרת.
void Stop();

}  // namespace startup_watchdog

#endif  // RUNNER_STARTUP_WATCHDOG_H_
