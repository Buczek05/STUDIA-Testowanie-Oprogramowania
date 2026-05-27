*** Settings ***
Documentation    Testy stresowe Simple EPC Simulator.
...              Weryfikują zachowanie serwera przy dużym obciążeniu i wykrywają brak
...              mechanizmów ochrony DoS: braku rate limitingu oraz braku limitu rozmiaru żądania.
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}              http://localhost:8000
${RESET_BURST_COUNT}     ${50}
${ATTACH_BURST_COUNT}    ${100}

*** Test Cases ***
ST-001 Reset Endpoint Nie Ma Rate Limitingu - Burst 50 Żądań
    [Documentation]    Wysyła 50 kolejnych żądań POST /reset bez żadnej przerwy.
    ...                Oczekiwany wynik: wszystkie 50 zwracają HTTP 200 (brak throttlingu).
    ...                Cel: udokumentowanie wektora DoS przez brak rate limitingu.
    [Tags]    stress    rate-limit    dos    reset
    Send ${RESET_BURST_COUNT} Consecutive Requests To Reset
    All Collected Responses Should Be 200

ST-002 Serwer Przyjmuje Payload 10 MB - Brak Limitu Rozmiaru
    [Documentation]    Wysyła POST /ues z dodatkowym polem o rozmiarze ~10 MB.
    ...                Oczekiwany wynik: serwer odpowiada bez błędu 5xx — przetwarza cały payload
    ...                przed walidacją zamiast odrzucić żądanie na wejściu po przekroczeniu limitu.
    ...                Cel: udokumentowanie braku limitu rozmiaru żądania (wektor OOM).
    [Tags]    stress    payload-size    dos
    Send Attach Request With 10000000 Byte Payload
    Response Should Not Be Server Error

ST-003 Serwer Przyjmuje Payload 100 MB - Brak Limitu Rozmiaru
    [Documentation]    Wysyła POST /ues z dodatkowym polem o rozmiarze ~100 MB.
    ...                Oczekiwany wynik: serwer odpowiada bez błędu 5xx.
    ...                Cel: demonstracja wyczerpania pamięci przez pojedyncze żądanie bez limitu.
    [Tags]    stress    payload-size    dos
    Send Attach Request With 100000000 Byte Payload
    Response Should Not Be Server Error

ST-004 Przepustowość Attach - Seryjne Podłączenie 100 UE
    [Documentation]    Podłącza kolejno 100 unikalnych UE (ID 1–100) i mierzy łączny czas.
    ...                Pozwala określić bazową przepustowość POST /ues i wykryć degradację wydajności.
    [Tags]    stress    throughput    attach
    Attach ${ATTACH_BURST_COUNT} UEs Sequentially
    UE List Should Contain ${ATTACH_BURST_COUNT} Entries

ST-005 Reset Pod Pełnym Obciążeniem - 100 UE W Stanie
    [Documentation]    Po attach 100 UE wysyła POST /reset i weryfikuje całkowite wyczyszczenie stanu.
    ...                Mierzy czas resetu przy pełnym obciążeniu symulatora.
    [Tags]    stress    reset    throughput
    Attach ${ATTACH_BURST_COUNT} UEs Sequentially
    Reset Should Wipe All State

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

Send ${count} Consecutive Requests To Reset
    [Documentation]    Wysyła ${count} żądań POST /reset i zapisuje kody odpowiedzi w ${LAST_RESPONSES}.
    ${responses}=    Create List
    ${start}=        Evaluate    __import__('time').time()
    FOR    ${i}    IN RANGE    ${count}
        ${resp}=    POST On Session    epc    /reset    expected_status=any
        Append To List    ${responses}    ${resp.status_code}
    END
    ${elapsed}=    Evaluate    round(__import__('time').time() - ${start}, 2)
    ${rps}=        Evaluate    round(${count} / ${elapsed}, 1)
    Log    ${count} żądań POST /reset: ${elapsed}s → ${rps} req/s    console=True
    Set Test Variable    ${LAST_RESPONSES}    ${responses}

All Collected Responses Should Be 200
    [Documentation]    Weryfikuje, że wszystkie zebrane kody odpowiedzi wynoszą 200.
    ${failures}=    Set Variable    ${0}
    FOR    ${code}    IN    @{LAST_RESPONSES}
        IF    ${code} != 200
            ${failures}=    Evaluate    ${failures} + 1
        END
    END
    ${total}=    Get Length    ${LAST_RESPONSES}
    Should Be Equal As Integers    ${failures}    0
    ...    ${failures} z ${total} żądań zwróciło kod != 200 — wykryto rate limiting

Send Attach Request With ${size} Byte Payload
    [Documentation]    Wysyła POST /ues z polem padding o rozmiarze ${size} bajtów i zapisuje odpowiedź.
    ${padding}=    Evaluate    "A" * ${size}
    ${body}=       Create Dictionary    ue_id=${1}    padding=${padding}
    ${start}=      Evaluate    __import__('time').time()
    ${resp}=       POST On Session    epc    /ues    json=${body}    expected_status=any    timeout=120
    ${elapsed}=    Evaluate    round(__import__('time').time() - ${start}, 3)
    Log    Payload ${size} B → HTTP ${resp.status_code} w ${elapsed}s    console=True
    Set Test Variable    ${LAST_RESPONSE}    ${resp}

Response Should Not Be Server Error
    [Documentation]    Weryfikuje, że ostatnia odpowiedź nie jest błędem serwera (5xx).
    Should Be True    ${LAST_RESPONSE.status_code} < 500
    ...    Serwer zwrócił 5xx — możliwy crash lub OOM

Attach ${count} UEs Sequentially
    [Documentation]    Podłącza sekwencyjnie ${count} UE (ID 1..${count}) i loguje przepustowość.
    ${end}=      Evaluate    ${count} + 1
    ${start}=    Evaluate    __import__('time').time()
    FOR    ${ue_id}    IN RANGE    1    ${end}
        ${body}=    Create Dictionary    ue_id=${ue_id}
        POST On Session    epc    /ues    json=${body}    expected_status=any
    END
    ${elapsed}=    Evaluate    round(__import__('time').time() - ${start}, 2)
    ${rps}=        Evaluate    round(${count} / ${elapsed}, 1)
    Log    ${count} attachów w ${elapsed}s → ${rps} req/s    console=True

UE List Should Contain ${count} Entries
    [Documentation]    Pobiera GET /ues i sprawdza, że lista zawiera ${count} elementów.
    ${list_resp}=    GET On Session    epc    /ues
    Length Should Be    ${list_resp.json()}[ues]    ${count}
    ...    Lista UE powinna zawierać ${count} elementów

Reset Should Wipe All State
    [Documentation]    Wysyła POST /reset, mierzy czas i weryfikuje, że GET /ues zwraca pustą listę.
    ${start}=     Evaluate    __import__('time').time()
    ${resp}=      POST On Session    epc    /reset
    ${elapsed}=   Evaluate    round(__import__('time').time() - ${start}, 3)
    Log    Reset w ${elapsed}s    console=True
    Status Should Be    200    ${resp}
    ${list_resp}=    GET On Session    epc    /ues
    Length Should Be    ${list_resp.json()}[ues]    0
    ...    Po resecie lista UE powinna być pusta
