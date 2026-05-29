*** Settings ***
Documentation    Testy funkcjonalności - usunięcie kanału transportowego z UE (delete bearer).
...              - Możliwe jest usunięcie dedykowanego bearer'a dla UE
...              - Procedura wymaga podania UE ID oraz bearer ID
...              - Bearer spoza zakresu -> błąd
...              - Bearer nieaktywny -> błąd
...              - Nie ma możliwości usunięcia domyślnego bearera
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}                http://localhost:8000
${VALID_UE_ID}             ${50}
${DEFAULT_BEARER_ID}       ${9}
${DEDICATED_BEARER_ID}     ${3}
${BEARER_ABOVE_RANGE}      ${10}
${BEARER_BELOW_RANGE}      ${0}
${UNATTACHED_UE_ID}        ${77}
${VALID_MBPS}              ${50}
${VALID_PROTOCOL}          tcp

*** Test Cases ***
T-046 Deleting an added dedicated bearer returns status bearer_deleted
    [Documentation]    Akcja: usunięcie wcześniej dodanego dedykowanego bearera dla podłączonego UE.
    ...                Oczekiwane: 200 ze statusem bearer_deleted oraz UE ID i bearer ID zgodnymi z żądaniem.
    [Tags]    delete-bearer    happy-path
    Attach UE ${VALID_UE_ID}
    Add bearer ${DEDICATED_BEARER_ID} to UE ${VALID_UE_ID}
    Delete bearer ${DEDICATED_BEARER_ID} from UE ${VALID_UE_ID}
    Delete bearer response should confirm UE ${VALID_UE_ID} bearer ${DEDICATED_BEARER_ID}

T-047 Deleted bearer no longer appears on the UE
    [Documentation]    Akcja: usunięcie dedykowanego bearera, a następnie odczyt danych UE.
    ...                Oczekiwane: usunięty bearer nie jest już obecny na liście bearerów UE.
    [Tags]    delete-bearer    state
    Attach UE ${VALID_UE_ID}
    Add bearer ${DEDICATED_BEARER_ID} to UE ${VALID_UE_ID}
    Delete bearer ${DEDICATED_BEARER_ID} from UE ${VALID_UE_ID}
    UE ${VALID_UE_ID} should not have bearer ${DEDICATED_BEARER_ID}

T-048 Deleting the default bearer 9 is forbidden
    [Documentation]    Akcja: próba usunięcia domyślnego bearera o ID 9 ustanowionego przy podłączeniu UE.
    ...                Oczekiwane: błąd - wg spec nie ma możliwości usunięcia domyślnego bearera.
    [Tags]    delete-bearer    forbidden
    Attach UE ${VALID_UE_ID}
    Deleting bearer ${DEFAULT_BEARER_ID} from UE ${VALID_UE_ID} should be rejected with message "Cannot remove default bearer"

T-049 Deleting a bearer that is not active is rejected
    [Documentation]    Akcja: dodanie i usunięcie bearera, a następnie ponowna próba usunięcia tego samego bearera.
    ...                Oczekiwane: błąd - wg spec usunięcie nieaktywnego bearera powinno zostać odrzucone.
    [Tags]    delete-bearer    error
    Attach UE ${VALID_UE_ID}
    Add bearer ${DEDICATED_BEARER_ID} to UE ${VALID_UE_ID}
    Delete bearer ${DEDICATED_BEARER_ID} from UE ${VALID_UE_ID}
    Deleting bearer ${DEDICATED_BEARER_ID} from UE ${VALID_UE_ID} should be rejected with message "Bearer not found"

T-050 Deleting a bearer above the valid range is rejected
    [Documentation]    Akcja: próba usunięcia bearera o ID 10 (powyżej zakresu 1-9 zdefiniowanego w kontrakcie).
    ...                Oczekiwane: błąd - procedura wymaga bearer ID z dozwolonego zakresu.
    [Tags]    delete-bearer    validation
    Attach UE ${VALID_UE_ID}
    Deleting bearer ${BEARER_ABOVE_RANGE} from UE ${VALID_UE_ID} should be rejected with message "Bearer not found"

T-051 Deleting a bearer below the valid range is rejected
    [Documentation]    Akcja: próba usunięcia bearera o ID 0 (poniżej zakresu 1-9 zdefiniowanego w kontrakcie).
    ...                Oczekiwane: błąd - procedura wymaga bearer ID z dozwolonego zakresu.
    [Tags]    delete-bearer    validation
    Attach UE ${VALID_UE_ID}
    Deleting bearer ${BEARER_BELOW_RANGE} from UE ${VALID_UE_ID} should be rejected with message "Bearer not found"

T-052 Deleting a bearer on an unattached UE is rejected
    [Documentation]    Akcja: próba usunięcia bearera dla UE, który nie został przyłączony do sieci.
    ...                Oczekiwane: błąd - procedura wg spec wymaga istniejącego UE ID.
    [Tags]    delete-bearer    error
    Deleting bearer ${DEDICATED_BEARER_ID} from UE ${UNATTACHED_UE_ID} should be rejected with message "UE not found"

T-067 Deleting a bearer with an active transfer is rejected
    [Documentation]    Akcja: uruchomienie transferu na dedykowanym bearerze, następnie próba jego usunięcia.
    ...                Oczekiwane: błąd - nie można usunąć bearera z aktywną sesją transferu,
    ...                transfer powinien zostać najpierw zatrzymany.
    [Tags]    delete-bearer    error
    Attach UE ${VALID_UE_ID}
    Add bearer ${DEDICATED_BEARER_ID} to UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEDICATED_BEARER_ID}
    Deleting bearer ${DEDICATED_BEARER_ID} from UE ${VALID_UE_ID} should be rejected

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

# --- Akcje domenowe (embedded arguments) ---

Attach UE ${ue_id}
    [Documentation]    Podłącza UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    ue_id=${ue_id}
    POST On Session    epc    /ues    json=${body}    expected_status=any

Add bearer ${bearer_id} to UE ${ue_id}
    [Documentation]    Dodaje dedykowany bearer do UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    bearer_id=${bearer_id}
    POST On Session    epc    /ues/${ue_id}/bearers    json=${body}    expected_status=any

Start traffic on UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Uruchamia transfer na bearerze (helper do przygotowania stanu).
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}    Mbps=${VALID_MBPS}
    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any

Delete bearer ${bearer_id} from UE ${ue_id}
    [Documentation]    Wysyła DELETE /ues/{ue_id}/bearers/{bearer_id} i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    DELETE On Session    epc    /ues/${ue_id}/bearers/${bearer_id}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

# --- Asercje domenowe (embedded arguments) ---

Delete bearer response should confirm UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Weryfikuje, że ostatnie usunięcie zwróciło 200 i body potwierdza UE oraz bearer ID.
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Strings     ${LAST_RESPONSE.json()}[status]       bearer_deleted
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[ue_id]        ${ue_id}
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[bearer_id]    ${bearer_id}

UE ${ue_id} should not have bearer ${bearer_id}
    [Documentation]    Pobiera dane UE i sprawdza, że podany bearer nie jest już obecny.
    ${ue}=    GET On Session    epc    /ues/${ue_id}
    Status Should Be    200    ${ue}
    ${key}=    Convert To String    ${bearer_id}
    Dictionary Should Not Contain Key    ${ue.json()}[bearers]    ${key}

Deleting bearer ${bearer_id} from UE ${ue_id} should be rejected
    [Documentation]    Próbuje usunąć bearer i weryfikuje, że API zwróciło błąd (status >= 400).
    Delete bearer ${bearer_id} from UE ${ue_id}
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    Delete bearer ${bearer_id} z UE ${ue_id} powinien zostać odrzucony, a API zwróciło ${LAST_RESPONSE.status_code}

Deleting bearer ${bearer_id} from UE ${ue_id} should be rejected with message "${substring}"
    [Documentation]    Jak wyżej, ale dodatkowo sprawdza fragment komunikatu błędu.
    Deleting bearer ${bearer_id} from UE ${ue_id} should be rejected
    Should Contain    ${LAST_RESPONSE.text}    ${substring}
