import random
import urllib.parse
from scapy.all import *

SQLI_PAYLOADS = [
    "' OR '1'='1",
    "' OR 1=1--",
    "\" OR \"1\"=\"1",
    "admin'--",
    "1 OR 1=1",
    "1' OR '1'='1",
    "' OR 'a'='a",
    "') OR ('1'='1",
]

def generate_bulk_sqli(filename, target_ip, target_port=80):
    """
    Membuat file PCAP berisi banyak sesi serangan SQLi.
    Setiap payload akan memiliki sesi TCP sendiri (beda port source).
    """

    all_packets = []
    attacker_ip = "192.168.1.100"

    print(f"[*] Memulai generate {len(SQLI_PAYLOADS)} serangan...")

    for i, raw_payload in enumerate(SQLI_PAYLOADS):
        client_port = random.randint(30000, 60000)
        client_seq = random.randint(1000, 50000)
        server_seq = random.randint(1000, 50000)
        encoded_payload = urllib.parse.quote(raw_payload)

        # TCP HANDSHAKE
        # SYN
        syn = IP(src=attacker_ip, dst=target_ip) / \
            TCP(sport=client_port, dport=target_port, flags='S', seq=client_seq)
        all_packets.append(syn)

        # SYN-ACK
        syn_ack = IP(src=target_ip, dst=attacker_ip) / \
            TCP(sport=target_port, dport=client_port,
                flags='SA', seq=server_seq, ack=client_seq + 1)
        all_packets.append(syn_ack)

        # ACK (Connection Established)
        client_seq += 1
        server_seq += 1
        ack = IP(src=attacker_ip, dst=target_ip) / \
            TCP(sport=client_port, dport=target_port,
                flags='A', seq=client_seq, ack=server_seq)
        all_packets.append(ack)

        # HTTP INJECTION
        # HTTP Request dengan Payload
        http_req_str = (
            f"GET /login.php?user={encoded_payload} HTTP/1.1\r\n"
            f"Host: {target_ip}\r\n"
            "User-Agent: Mozilla/5.0 (compatible; SQLScanner/1.0)\r\n"
            "Accept: */*\r\n"
            "\r\n"
        )

        http_req = IP(src=attacker_ip, dst=target_ip) / \
            TCP(sport=client_port, dport=target_port, flags='PA', seq=client_seq, ack=server_seq) / \
            http_req_str
        all_packets.append(http_req)
        client_seq += len(http_req_str)

        # HTTP Response (Simulasi Error atau Sukses)
        http_resp_str = (
            "HTTP/1.1 200 OK\r\n"
            "Content-Type: text/html\r\n"
            "Content-Length: 20\r\n"
            "\r\n"
            "Invalid User Input."
        )

        http_resp = IP(src=target_ip, dst=attacker_ip) / \
            TCP(sport=target_port, dport=client_port, flags='PA', seq=server_seq, ack=client_seq) / \
            http_resp_str
        all_packets.append(http_resp)
        server_seq += len(http_resp_str)

        # TEARDOWN (TUTUP KONEKSI)
        # FIN-ACK dari Client
        fin = IP(src=attacker_ip, dst=target_ip) / \
            TCP(sport=client_port, dport=target_port,
                flags='FA', seq=client_seq, ack=server_seq)
        all_packets.append(fin)

        # FIN-ACK dari Server
        fin_ack = IP(src=target_ip, dst=attacker_ip) / \
            TCP(sport=target_port, dport=client_port,
                flags='FA', seq=server_seq, ack=client_seq + 1)
        all_packets.append(fin_ack)

        # Final ACK
        final_ack = IP(src=attacker_ip, dst=target_ip) / \
            TCP(sport=client_port, dport=target_port, flags='A',
                seq=client_seq + 1, ack=server_seq + 1)
        all_packets.append(final_ack)

    # Tulis semua paket ke file
    wrpcap(filename, all_packets)
    print(
        f"[+] Selesai! File '{filename}' telah dibuat dengan total {len(all_packets)} paket.")


if __name__ == "__main__":
    generate_bulk_sqli("multi_attack_sqli.pcap", "172.16.10.120")