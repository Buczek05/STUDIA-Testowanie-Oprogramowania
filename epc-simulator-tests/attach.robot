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

*** Test Cases ***
T-001 Attach UE With Valid ID Succeeds
    [Documentation]    UE o poprawnym ID zostaje podłączony, API potwierdza status.
    [Tags]    attach    happy-path
    Attach UE-50
    Verify Attach Succeeded-50

T-002 Attached UE Receives Default Bearer 9
    [Documentation]    Po attachu UE ma automatycznie ustanowiony domyślny bearer o ID 9.
    [Tags]    attach    default-bearer
    Attach UE-50
    UE Should Have Default Bearer-50-9

T-003 Attach UE With Out Of Range ID Is Rejected
    [Documentation]    UE ID poza zakresem dopuszczalnych wartości -> błąd.
    [Tags]    attach    validation
    Verify Attach was Rejected--1

T-004 Attach Already Attached UE Is Rejected
    [Documentation]    Ponowny attach tego samego UE -> błąd (spec: "UE już podłączony").
    [Tags]    attach    conflict
    Attach UE-50
    Verify Attach Was Rejected With Message-50    already attached

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

Attach UE-${ue_id}
    [Documentation]    Wysyła attach UE i zapisuje odpowiedź w ${LAST_RESPONSE}.
    # [Arguments]    ${ue_id}
    ${body}=    Create Dictionary    ue_id=${ue_id}
    ${response}=    POST On Session    epc    /ues    json=${body}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}


Verify Attach Succeeded-${ue_id}
    [Documentation]    Weryfikuje, że ostatni attach zwrócił 200 i poprawne body (status=attached, ue_id zgodny).
    # [Arguments]    ${ue_id}
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Strings     ${LAST_RESPONSE.json()}[status]    attached
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[ue_id]     ${ue_id}

UE Should Have Default Bearer-${ue_id}-${bearer_id}
    [Documentation]    Pobiera dane UE i sprawdza, że ma domyślny bearer o ID 9.
    # [Arguments]    ${ue_id}
    ${ue}=    GET On Session    epc    /ues/${ue_id}
    Status Should Be    200    ${ue}
    Dictionary Should Contain Key    ${ue.json()}[bearers]    9
    Should Be Equal As Integers      ${ue.json()}[bearers][9][bearer_id]    ${bearer_id}

Verify Attach was Rejected-${ue_id}
    [Documentation]    Próbuje attach i weryfikuje, że API zwróciło błąd (status >= 400).
    #[Arguments]    ${ue_id}
    Attach UE-${ue_id}
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    UE ID ${ue_id} powinien zostać odrzucony, a API zwróciło ${LAST_RESPONSE.status_code}

Verify Attach Was Rejected With Message-${ue_id}
    [Documentation]    Jak "Attach Should Be Rejected", ale dodatkowo sprawdza fragment komunikatu błędu.
    [Arguments]    ${substring}
    Verify Attach was Rejected-${ue_id}
    Should Contain    ${LAST_RESPONSE.text}    ${substring}