*** Settings ***
Documentation    Testy funkcjonalności - odłączenie UE od sieci (detach).
...              - UE może zostać odłączony od sieci (wymaga UE ID)
...              - Jeśli UE nie jest podłączony -> błąd
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}        http://localhost:8000
${VALID_UE_ID}     ${50}

*** Test Cases ***
T-005 Detaching an attached UE returns status detached
    [Documentation]    Happy path - UE podłączony zostaje odłączony, API potwierdza status.
    [Tags]    detach    happy-path
    Attach UE ${VALID_UE_ID}
    Detach UE ${VALID_UE_ID}
    Detach response should confirm UE ${VALID_UE_ID}

T-006 Detached UE no longer appears on the UE list
    [Documentation]    Weryfikacja skutku - UE znika z GET /ues.
    [Tags]    detach    state
    Attach UE ${VALID_UE_ID}
    Detach UE ${VALID_UE_ID}
    UE ${VALID_UE_ID} should not be present

T-007 Detaching a UE that was never attached is rejected
    [Documentation]    Błąd zgodny ze specyfikacją - "UE nie jest podłączony".
    [Tags]    detach    error
    Detaching UE ${VALID_UE_ID} should be rejected with message "not found"

T-008 Detaching the same UE twice is rejected on the second attempt
    [Documentation]    Drugi detach trafia na odłączonego UE -> błąd.
    [Tags]    detach    error
    Attach UE ${VALID_UE_ID}
    Detach UE ${VALID_UE_ID}
    Detaching UE ${VALID_UE_ID} should be rejected

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

# --- Akcje domenowe (embedded arguments) ---

Attach UE ${ue_id}
    [Documentation]    Podłącza UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    ue_id=${ue_id}
    POST On Session    epc    /ues    json=${body}    expected_status=any

Detach UE ${ue_id}
    [Documentation]    Wysyła DELETE /ues/{id} i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    DELETE On Session    epc    /ues/${ue_id}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

# --- Asercje domenowe (embedded arguments) ---

Detach response should confirm UE ${ue_id}
    [Documentation]    Weryfikuje, że ostatni detach zwrócił 200 i body potwierdza podane UE ID.
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Strings     ${LAST_RESPONSE.json()}[status]    detached
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[ue_id]     ${ue_id}

UE ${ue_id} should not be present
    [Documentation]    Sprawdza, że UE nie jest na liście podłączonych.
    ${list}=    GET On Session    epc    /ues
    List Should Not Contain Value    ${list.json()}[ues]    ${ue_id}

Detaching UE ${ue_id} should be rejected
    [Documentation]    Próbuje detach i weryfikuje, że API zwróciło błąd (status >= 400).
    Detach UE ${ue_id}
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    Detach UE ${ue_id} powinien zostać odrzucony, a API zwróciło ${LAST_RESPONSE.status_code}

Detaching UE ${ue_id} should be rejected with message "${substring}"
    [Documentation]    Jak wyżej, ale dodatkowo sprawdza fragment komunikatu błędu.
    Detaching UE ${ue_id} should be rejected
    Should Contain    ${LAST_RESPONSE.text}    ${substring}
