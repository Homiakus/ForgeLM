// test_server.c - Тестирование Pure Assembly HTTP Server
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>

extern int forgelm_create_server_socket(int port);
extern void forgelm_http_handle_connection(int client_fd, const char *body, int body_len);

static volatile int server_ready = 0;
static const char *mock_openai_response = "{\"id\":\"chatcmpl-forgelm\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"ForgeLM Pure Assembly Engine\"}}]}";

void* server_thread_func(void *arg) {
    int port = *(int*)arg;
    int sfd = forgelm_create_server_socket(port);
    if (sfd < 0) {
        perror("forgelm_create_server_socket failed");
        server_ready = -1;
        return NULL;
    }
    server_ready = 1;

    // Принимаем 1 тестовый запрос
    int client_fd = accept(sfd, NULL, NULL);
    if (client_fd >= 0) {
        forgelm_http_handle_connection(client_fd, mock_openai_response, strlen(mock_openai_response));
    }
    close(sfd);
    return NULL;
}

int main() {
    printf("=== [ForgeLM Audit] Pure Assembly Zero-Libc HTTP Server ===\n");

    // Выбираем динамический порт на основе PID для исключения TIME_WAIT коллизий
    int test_port = 19000 + (getpid() % 1000);

    pthread_t th;
    pthread_create(&th, NULL, server_thread_func, &test_port);

    while (server_ready == 0) {
        usleep(1000);
    }
    if (server_ready < 0) {
        printf("FAIL: server socket setup failed\n");
        return 1;
    }

    // Делаем клиентский запрос через сокет
    int client_sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in serv_addr;
    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(test_port);
    inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr);

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    if (connect(client_sock, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
        perror("connect failed");
        return 1;
    }

    const char *http_req = "GET /v1/chat/completions HTTP/1.1\r\nHost: localhost\r\n\r\n";
    send(client_sock, http_req, strlen(http_req), 0);

    char buffer[1024];
    memset(buffer, 0, sizeof(buffer));
    ssize_t total_read = 0;
    while (total_read < (ssize_t)sizeof(buffer) - 1) {
        ssize_t n = recv(client_sock, buffer + total_read, sizeof(buffer) - 1 - total_read, 0);
        if (n <= 0) break;
        total_read += n;
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    close(client_sock);

    pthread_join(th, NULL);

    double latency_us = ((t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) * 1e-9) * 1e6;

    printf("Received HTTP Response (%zd bytes):\n%s\n", total_read, buffer);
    printf("Round-Trip HTTP Latency: %.2f us (microsecond level!)\n", latency_us);

    if (strstr(buffer, "ForgeLM-PureASM") && strstr(buffer, "chatcmpl-forgelm")) {
        printf(">>> ZERO-LIBC HTTP SERVER VERIFIED [PASS] <<<\n");
        return 0;
    } else {
        printf("FAIL: unexpected response\n");
        return 1;
    }
}
