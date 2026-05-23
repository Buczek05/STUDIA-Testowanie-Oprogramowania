*** Settings ***
Documentation    Testy funkcjonalności - podłączenie UE do sieci (attach).
...              - UE może zostać dołączony do sieci (wymaga UE ID)
...              - UE ID spoza zakresu -> błąd
...              - UE już podłączony -> błąd
...              - Podłączony UE automatycznie otrzymuje domyślny bearer ID 9
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}              http://localhost:8000
${DEFAULT_BEARER_ID}     ${9}
${VALID_UE_ID}           ${50}
${INVALID_UE_ID}         ${-1}

*** Test Cases ***
T-001 Attaching a UE with a valid ID returns status attached
    [Documentation]    Happy path - API potwierdza podłączenie w odpowiedzi.
    [Tags]    attach    happy-path
    Attach UE ${VALID_UE_ID}
    Attach response should confirm UE ${VALID_UE_ID}

T-002 Attaching a UE provisions it with default bearer 9
    [Documentation]    Po attachu UE ma automatycznie ustanowiony domyślny bearer o ID 9.
    [Tags]    attach    default-bearer
    Attach UE ${VALID_UE_ID}
    UE ${VALID_UE_ID} should have default bearer

T-003 Attaching a UE with an out-of-range ID is rejected
    [Documentation]    UE ID poza zakresem -> błąd.
    [Tags]    attach    validation
    Attaching UE ${INVALID_UE_ID} should be rejected

T-004 Re-attaching the same UE is rejected with an already attached error
    [Documentation]    Ponowny attach tego samego UE -> błąd z konkretnym komunikatem.
    [Tags]    attach    conflict
    Attach UE ${VALID_UE_ID}
    Attaching UE ${VALID_UE_ID} should be rejected with message "already attached"

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

# --- Akcje domenowe (embedded arguments) ---

Attach UE ${ue_id}
    [Documentation]    Wysyła POST /ues z UE ID i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${body}=    Create Dictionary    ue_id=${ue_id}
    ${response}=    POST On Session    epc    /ues    json=${body}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

# --- Asercje domenowe (embedded arguments) ---

Attach response should confirm UE ${ue_id}
    [Documentation]    Weryfikuje, że ostatni attach zwrócił 200 i body potwierdza podane UE ID.
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Strings     ${LAST_RESPONSE.json()}[status]    attached
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[ue_id]     ${ue_id}

UE ${ue_id} should have default bearer
    [Documentation]    Pobiera dane UE i sprawdza, że ma domyślny bearer o ID 9.
    ${ue}=    GET On Session    epc    /ues/${ue_id}
    Status Should Be    200    ${ue}
    Dictionary Should Contain Key    ${ue.json()}[bearers]    9
    Should Be Equal As Integers      ${ue.json()}[bearers][9][bearer_id]    ${DEFAULT_BEARER_ID}

Attaching UE ${ue_id} should be rejected
    [Documentation]    Próbuje attach i weryfikuje, że API zwróciło błąd (status >= 400).
    Attach UE ${ue_id}
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    UE ID ${ue_id} powinien zostać odrzucony, a API zwróciło ${LAST_RESPONSE.status_code}

Attaching UE ${ue_id} should be rejected with message "${substring}"
    [Documentation]    Jak wyżej, ale dodatkowo sprawdza fragment komunikatu błędu.
    Attaching UE ${ue_id} should be rejected
    Should Contain    ${LAST_RESPONSE.text}    ${substring}
