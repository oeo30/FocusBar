import UserNotifications

enum TBNotification {
    enum Category: String {
        case workFinished, restFinished
    }

    enum Action: String {
        case startRest, startWork
    }
}

typealias TBNotificationHandler = (TBNotification.Action) -> Void

class TBNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    private var center = UNUserNotificationCenter.current()
    private var handler: TBNotificationHandler?

    override init() {
        super.init()

        center.requestAuthorization(
            options: [.alert]
        ) { _, error in
            if error != nil {
                print("Error requesting notification authorization: \(error!)")
            }
        }

        center.delegate = self

        let actionStartRest = UNNotificationAction(
            identifier: TBNotification.Action.startRest.rawValue,
            title: NSLocalizedString("TBTimer.workFinished.action", comment: "Start rest"),
            options: []
        )
        let actionStartWork = UNNotificationAction(
            identifier: TBNotification.Action.startWork.rawValue,
            title: NSLocalizedString("TBTimer.restFinished.action", comment: "Start study"),
            options: []
        )
        let workFinishedCategory = UNNotificationCategory(
            identifier: TBNotification.Category.workFinished.rawValue,
            actions: [actionStartRest],
            intentIdentifiers: []
        )
        let restFinishedCategory = UNNotificationCategory(
            identifier: TBNotification.Category.restFinished.rawValue,
            actions: [actionStartWork],
            intentIdentifiers: []
        )

        center.setNotificationCategories([
            workFinishedCategory,
            restFinishedCategory,
        ])
    }

    func setActionHandler(handler: @escaping TBNotificationHandler) {
        self.handler = handler
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler _: @escaping () -> Void)
    {
        if handler != nil {
            if let action = TBNotification.Action(rawValue: response.actionIdentifier) {
                handler!(action)
            }
        }
    }

    func send(title: String, body: String, category: TBNotification.Category) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if error != nil {
                print("Error adding notification: \(error!)")
            }
        }
    }
}
