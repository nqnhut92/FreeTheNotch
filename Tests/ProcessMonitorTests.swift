import Foundation
import Testing

struct ProcessMonitorTests {
    @Test func groupsRowsPerOwnerLargestFirst() {
        let rows = [
            ProcessRow(pid: 1, name: "Safari", icon: nil, value: 10, downBps: 5),
            ProcessRow(pid: 2, name: "Mail", icon: nil, value: 25),
            ProcessRow(pid: 1, name: "Safari", icon: nil, value: 20, upBps: 3),
        ]
        let grouped = ProcessMonitor.grouped(rows)
        #expect(grouped.map(\.pid) == [1, 2])
        #expect(grouped[0].value == 30)
        #expect(grouped[0].downBps == 5)
        #expect(grouped[0].upBps == 3)
        #expect(grouped[1].downBps == nil)
    }

    @Test(arguments: [
        ("pid 437, WindowServer", pid_t?.some(437)),
        ("pid 1, launchd", 1),
        ("WindowServer", nil),
        ("pid , nothing", nil),
        ("", nil),
    ])
    func pidFromCreator(_ creator: String, expected: pid_t?) {
        #expect(ProcessMonitor.pidFromCreator(creator) == expected)
    }

    @Test func nettopKeepsOnlyTheSecondBlock() {
        let output = """
            time,,bytes_in,bytes_out,
            15:02:08.110000,MSTeams.730,999999,888888,
            15:02:08.110000,kernel_task.0,5,5,
            time,,bytes_in,bytes_out,
            15:02:09.224695,MSTeams.730,10404,36328,
            15:02:09.224695,Safari.1234,0,0,
            15:02:09.224695,com.apple.WebKi.99,100,0,
            15:02:09.224695,garbage,
            15:02:09.224695,noPid,1,1,

            """
        #expect(
            ProcessMonitor.parseNettop(output) == [
                ProcessMonitor.NettopSample(pid: 730, bytesIn: 10404, bytesOut: 36328),
                ProcessMonitor.NettopSample(pid: 99, bytesIn: 100, bytesOut: 0),
            ])
    }

    @Test func nettopWithoutASecondBlockHasNoRows() {
        #expect(ProcessMonitor.parseNettop("time,,bytes_in,bytes_out,\n15:02,App.1,10,10,\n").isEmpty)
    }
}
