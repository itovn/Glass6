// g6cpu — đo CPU của vài tiến trình trên máy iOS thử (máy iOS 6 không có ps / top).
//   g6cpu <giây> <tên tiến trình>…     vd: g6cpu 10 backboardd SpringBoard
//   g6cpu -l                            mọi tiến trình: «pid<TAB>RAM thường trú (KB)<TAB>tổng giây CPU<TAB>tên»
// In phần trăm CPU trung bình của từng tiến trình trong khoảng đo. Chạy quyền root. Công cụ thử, không đóng vào gói.
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>

// libproc (iOS SDK không kèm tệp đầu)
#define PROC_PIDTASKINFO 4
struct proc_taskinfo {
    uint64_t pti_virtual_size, pti_resident_size, pti_total_user, pti_total_system, pti_threads_user, pti_threads_system;
    int32_t pti_policy, pti_faults, pti_pageins, pti_cow_faults, pti_messages_sent, pti_messages_received, pti_syscalls_mach,
        pti_syscalls_unix, pti_csw, pti_threadnum, pti_numrunning, pti_priority;
};
int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);

static int find_pid(const char *name) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0) return -1;
    struct kinfo_proc *procs = malloc(len);
    if (!procs || sysctl(mib, 4, procs, &len, NULL, 0) != 0) return -1;
    int pid = -1;
    for (size_t i = 0; i < len / sizeof(*procs); i++) {
        if (strcmp(procs[i].kp_proc.p_comm, name) == 0) pid = procs[i].kp_proc.p_pid;
    }
    free(procs);
    return pid;
}

// Tổng thời gian CPU (nano giây) của một tiến trình; 0 nếu không đọc được
static uint64_t cpu_ns(int pid) {
    struct proc_taskinfo ti;
    if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, sizeof(ti)) != (int)sizeof(ti)) return 0;
    return ti.pti_total_user + ti.pti_total_system;
}

// Mọi tiến trình đang chạy kèm RAM thường trú và tổng thời gian CPU — để biết dịch vụ nào thật sự tốn máy
static int list_all(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0) return 1;
    len += 16 * sizeof(struct kinfo_proc);
    struct kinfo_proc *procs = malloc(len);
    if (!procs || sysctl(mib, 4, procs, &len, NULL, 0) != 0) return 1;
    for (size_t i = 0; i < len / sizeof(*procs); i++) {
        int pid = procs[i].kp_proc.p_pid;
        struct proc_taskinfo ti;
        if (pid <= 0 || proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, sizeof(ti)) != (int)sizeof(ti)) continue;
        printf("%d\t%llu\t%.1f\t%s\n", pid, (unsigned long long)(ti.pti_resident_size / 1024),
               (double)(ti.pti_total_user + ti.pti_total_system) / 1e9, procs[i].kp_proc.p_comm);
    }
    free(procs);
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "-l") == 0) return list_all();
    if (argc < 3) {
        fprintf(stderr, "dung: g6cpu <giay> <ten tien trinh>...\n");
        return 2;
    }
    int secs = atoi(argv[1]);
    if (secs < 1) secs = 5;
    int n = argc - 2;
    int pids[16];
    uint64_t before[16];
    if (n > 16) n = 16;
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    for (int i = 0; i < n; i++) {
        pids[i] = find_pid(argv[i + 2]);
        before[i] = pids[i] > 0 ? cpu_ns(pids[i]) : 0;
    }
    uint64_t t0 = mach_absolute_time();
    sleep(secs);
    double wall = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom;
    for (int i = 0; i < n; i++) {
        if (pids[i] <= 0) {
            printf("%s: khong thay\n", argv[i + 2]);
            continue;
        }
        // Thời gian CPU của tiến trình tính theo đơn vị của mach_absolute_time
        double used = (double)(cpu_ns(pids[i]) - before[i]) * tb.numer / tb.denom;
        printf("%s (pid %d): %.1f%% CPU\n", argv[i + 2], pids[i], used * 100.0 / wall);
    }
    return 0;
}
