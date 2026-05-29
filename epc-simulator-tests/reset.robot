*** Settings ***
Documentation    Testy funkcjonalności - zresetowanie symulatora (reset).
...              - Możliwe jest przywrócenie symulatora do stanu początkowego
...              - Reset czyści listę przyłączonych UE oraz aktywne transfery
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}              http://localhost:8000
${SAMPLE_UE_ID}          ${50}
${DEFAULT_BEARER_ID}     ${9}
${VALID_MBPS}            ${50}
${VALID_PROTOCOL}        tcp

*** Test Cases ***
T-053 Reset returns status reset
    [Documentation]    Akcja: wywołanie POST /reset na symulatorze.
    ...                Oczekiwane: 200 ze statusem reset potwierdzającym przywrócenie stanu początkowego.
    [Tags]    reset    happy-path
    Reset simulator
    Reset response should confirm

T-054 Reset clears attached UEs
    [Documentation]    Akcja: przyłączenie UE, a następnie reset symulatora.
    ...                Oczekiwane: po resecie lista przyłączonych UE jest pusta.
    [Tags]    reset    state
    Attach UE ${SAMPLE_UE_ID}
    List UEs
    UE list should contain UE ${SAMPLE_UE_ID}
    Reset simulator
    Reset response should confirm
    List UEs
    UE list should be empty

T-055 Reset is idempotent on an already empty state
    [Documentation]    Akcja: dwukrotne wywołanie resetu, drugi raz na już pustym stanie.
    ...                Oczekiwane: każdy reset zwraca 200, a lista UE pozostaje pusta.
    [Tags]    reset    idempotency    state
    Reset simulator
    Reset response should confirm
    Reset simulator
    Reset response should confirm
    List UEs
    UE list should be empty

T-056 Reset clears an active transfer
    [Documentation]    Akcja: przyłączenie UE, rozpoczęcie transferu, a następnie reset symulatora.
    ...                Oczekiwane: po resecie lista przyłączonych UE jest pusta - aktywny transfer również zostaje usunięty.
    [Tags]    reset    state    transfer
    Attach UE ${SAMPLE_UE_ID}
    Start traffic for UE ${SAMPLE_UE_ID} on bearer ${DEFAULT_BEARER_ID}
    Reset simulator
    Reset response should confirm
    List UEs
    UE list should be empty

T-057 Reset via wrong HTTP method is rejected
    [Documentation]    Akcja: wywołanie /reset metodą GET zamiast POST.
    ...                Oczekiwane: błąd - niedozwolona metoda (405 Method Not Allowed).
    [Tags]    reset    method    error
    Resetting via GET should be rejected

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

# --- Akcje domenowe (embedded arguments) ---

Attach UE ${ue_id}
    [Documentation]    Podłącza UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    ue_id=${ue_id}
    POST On Session    epc    /ues    json=${body}    expected_status=any

Start traffic for UE ${ue_id} on bearer ${bearer_id}
    [Documentation]    Rozpoczyna transfer na bearerze UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}    Mbps=${VALID_MBPS}
    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any

Reset simulator
    [Documentation]    Wysyła POST /reset i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    POST On Session    epc    /reset    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

List UEs
    [Documentation]    Pobiera listę przyłączonych UE (GET /ues) i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    GET On Session    epc    /ues    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Reset via GET
    [Documentation]    Wysyła GET /reset (zła metoda) i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    GET On Session    epc    /reset    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

# --- Asercje domenowe (embedded arguments) ---

Reset response should confirm
    [Documentation]    Weryfikuje, że ostatni reset zwrócił 200 i body potwierdza status reset.
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Strings     ${LAST_RESPONSE.json()}[status]    reset

UE list should be empty
    [Documentation]    Weryfikuje, że GET /ues zwrócił 200 i pustą listę przyłączonych UE.
    Status Should Be    200    ${LAST_RESPONSE}
    Should Be Empty     ${LAST_RESPONSE.json()}[ues]

UE list should contain UE ${ue_id}
    [Documentation]    Weryfikuje, że GET /ues zwrócił 200 i lista zawiera podane UE ID.
    Status Should Be              200    ${LAST_RESPONSE}
    List Should Contain Value     ${LAST_RESPONSE.json()}[ues]    ${ue_id}

Resetting via GET should be rejected
    [Documentation]    Próbuje wywołać reset metodą GET i weryfikuje, że API odrzuciło żądanie (405 - niedozwolona metoda).
    Reset via GET
    Should Be Equal As Integers    ${LAST_RESPONSE.status_code}    405
    ...    GET /reset powinien zostać odrzucony jako niedozwolona metoda, a API zwróciło ${LAST_RESPONSE.status_code}
