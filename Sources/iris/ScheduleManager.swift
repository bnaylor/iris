import Foundation
import AppKit

struct ScheduledJob: Codable, Identifiable {
    var id: UUID = UUID()
    let conversationId: UUID?
    let prompt: String
    
    // Date components for matching. Nil means "any/wildcard"
    let minute: Int?
    let hour: Int?
    let day: Int?
    let month: Int?
    let weekday: Int? // 1 = Sunday, 2 = Monday, etc.
    
    // For one-off timers or simple intervals
    let intervalSeconds: Int?
    
    var nextFireAt: Date
    
    func calculateNextFireDate(after date: Date) -> Date {
        if let interval = intervalSeconds {
            return date.addingTimeInterval(TimeInterval(interval))
        }
        
        var comps = DateComponents()
        if let minute = minute { comps.minute = minute }
        if let hour = hour { comps.hour = hour }
        if let day = day { comps.day = day }
        if let month = month { comps.month = month }
        if let weekday = weekday { comps.weekday = weekday }
        
        // If we want it to trigger on matching boundaries, we use .nextTime
        let next = Calendar.current.nextDate(after: date, matching: comps, matchingPolicy: .nextTime) 
        return next ?? date.addingTimeInterval(86400) // Fallback just in case
    }
}

class ScheduleManager: @unchecked Sendable {
    static let shared = ScheduleManager()
    
    private let queue = DispatchQueue(label: "com.iris.scheduler")
    private var jobs: [ScheduledJob] = []
    private var timer: Timer?
    
    var onJobFired: ((String, UUID?) async -> Void)?
    
    private init() {
        loadJobs()
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluateJobs(fromWake: true)
        }
    }
    
    func start() {
        queue.async {
            self.timer?.invalidate()
            // Evaluate every 10 seconds to not miss minute marks
            self.timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                self?.evaluateJobs(fromWake: false)
            }
            RunLoop.current.add(self.timer!, forMode: .default)
            RunLoop.current.run()
        }
    }
    
    func schedule(conversationId: UUID?, prompt: String, minute: Int? = nil, hour: Int? = nil, day: Int? = nil, month: Int? = nil, weekday: Int? = nil, intervalSeconds: Int? = nil) {
        queue.async {
            var job = ScheduledJob(
                conversationId: conversationId,
                prompt: prompt,
                minute: minute,
                hour: hour,
                day: day,
                month: month,
                weekday: weekday,
                intervalSeconds: intervalSeconds,
                nextFireAt: Date() // placeholder
            )
            job.nextFireAt = job.calculateNextFireDate(after: Date())
            self.jobs.append(job)
            self.saveJobs()
        }
    }
    
    private func evaluateJobs(fromWake: Bool) {
        queue.async {
            let now = Date()
            var firedJobs: [ScheduledJob] = []
            var updatedJobs: [ScheduledJob] = []
            
            for var job in self.jobs {
                if job.nextFireAt <= now {
                    firedJobs.append(job)
                    // Set next fire date relative to NOW, not relative to when it missed (to prevent firing a million times catching up)
                    job.nextFireAt = job.calculateNextFireDate(after: now)
                    
                    // Keep the job if it's recurring. If it was an interval, we also recur?
                    // Let's assume all cron and interval jobs recur. If they want one-off, we could add `isRecurring`.
                    // Actually, let's just make everything recurring for simplicity.
                    updatedJobs.append(job) 
                } else {
                    updatedJobs.append(job)
                }
            }
            
            if !firedJobs.isEmpty {
                self.jobs = updatedJobs
                self.saveJobs()
                
                for job in firedJobs {
                    Task {
                        await self.onJobFired?(job.prompt, job.conversationId)
                    }
                }
            }
        }
    }
    
    private func loadJobs() {
        if let data = UserDefaults.standard.data(forKey: "iris_scheduled_jobs"),
           let decoded = try? JSONDecoder().decode([ScheduledJob].self, from: data) {
            self.jobs = decoded
        }
    }
    
    private func saveJobs() {
        if let encoded = try? JSONEncoder().encode(jobs) {
            UserDefaults.standard.set(encoded, forKey: "iris_scheduled_jobs")
        }
    }
}
