#!/bin/bash

# Variables globales
DOMAIN_NAME="HOSPITALPATOLOGIA.local"
OU_PATH="OU=Usuarios,DC=HOSPITALPATOLOGIA,DC=local"

# Archivo donde se almacenarán los datos de los usuarios
USERS_FILE="users.txt"

# Función para mostrar el menú principal del CRUD
show_menu() {
    echo "=== Gestión de Usuarios ==="
    echo "1. Crear usuario"
    echo "2. Listar usuarios"
    echo "3. Actualizar usuario"
    echo "4. Eliminar usuario"
    echo "5. Salir"
    echo ""
    read -p "Selecciona una opción: " option
    handle_option $option
}

# Función para manejar la opción seleccionada
handle_option() {
    case $1 in
        1) create_user ;;
        2) list_users ;;
        3) update_user ;;
        4) delete_user ;;
        5) exit ;;
        *) echo "Opción no válida"; sleep 2 ;;
    esac
}

# Función para crear OU (Organizational Unit) en Active Directory
create_ou() {
    local ou_name=$1
    if ! (powershell "Get-ADOrganizationalUnit -Filter {Name -eq '$ou_name'}" 2>/dev/null); then
        powershell "New-ADOrganizationalUnit -Name '$ou_name' -Path 'DC=HOSPITALPATOLOGIA,DC=local'"
        echo "Unidad Organizacional '$ou_name' creada."
    else
        echo "Unidad Organizacional '$ou_name' ya existe."
    fi
}

# Función para crear usuario en Active Directory
create_user_ad() {
    local username=$1
    local firstname=$2
    local lastname=$3
    local password=$4
    local ou=$5

    # Verificar si el usuario ya existe
    if ! (powershell "Get-ADUser -Filter {SamAccountName -eq '$username'}" 2>/dev/null); then
        powershell "New-ADUser -Name '$firstname $lastname' -GivenName '$firstname' -Surname '$lastname' -SamAccountName '$username' -UserPrincipalName '$username@$DOMAIN_NAME' -Path '$ou' -AccountPassword (ConvertTo-SecureString '$password' -AsPlainText -Force) -Enabled \$true"
        echo "Usuario '$username' creado exitosamente en Active Directory."
    else
        echo "El usuario '$username' ya existe en Active Directory."
    fi
}

# Función para asignar roles a usuarios
assign_role() {
    local username=$1
    local role=$2

    case $role in
        "Patologo")
            powershell "Add-ADGroupMember -Identity 'Grupo_Patologos' -Members '$username'"
            ;;
        "Tecnico")
            powershell "Add-ADGroupMember -Identity 'Grupo_Tecnicos' -Members '$username'"
            ;;
        "Administrativo")
            powershell "Add-ADGroupMember -Identity 'Grupo_Administrativos' -Members '$username'"
            ;;
        *)
            echo "Rol no reconocido para el usuario '$username'."
            ;;
    esac
}

# Función para crear un usuario en el archivo y en Active Directory
create_user() {
    clear
    echo "=== Crear Usuario ==="
    read -p "Nombre de usuario: " username
    read -p "Nombre: " firstname
    read -p "Apellido: " lastname
    read -p "Contraseña: " password
    read -p "Rol (Patologo/Tecnico/Administrativo): " role

    # Validar si el usuario ya existe
    if grep -q "^$username:" "$USERS_FILE" 2>/dev/null; then
        echo "El usuario '$username' ya existe."
        sleep 2
    else
        echo "$username:$password:$role:$firstname:$lastname" >> "$USERS_FILE"
        echo "Usuario '$username' creado exitosamente en el archivo."

        # Crear usuario en Active Directory
        create_user_ad "$username" "$firstname" "$lastname" "$password" "OU=${role}s,$OU_PATH"
        assign_role "$username" "$role"
        sleep 2
    fi
    show_menu
}

# Función para listar usuarios
list_users() {
    clear
    echo "=== Lista de Usuarios ==="
    if [ -f "$USERS_FILE" ]; then
        cat "$USERS_FILE" | awk -F: '{print "Usuario: " $1 ", Rol: " $3}'
    else
        echo "No hay usuarios registrados."
    fi
    echo ""
    read -p "Presiona Enter para continuar..."
    show_menu
}

# Función para actualizar un usuario
update_user() {
    clear
    echo "=== Actualizar Usuario ==="
    read -p "Nombre de usuario a actualizar: " username
    if grep -q "^$username:" "$USERS_FILE" 2>/dev/null; then
        read -p "Nueva contraseña: " new_password
        read -p "Nuevo rol (Patologo/Tecnico/Administrativo): " new_role

        # Actualizar el usuario
        sed -i "s/^$username:[^:]*:[^:]*:[^:]*:[^:]*\$/$username:$new_password:$new_role/" "$USERS_FILE"
        echo "Usuario '$username' actualizado exitosamente en el archivo."

        # Actualizar usuario en Active Directory
        create_user_ad "$username" "$(awk -F: -v user="$username" '$1 == user {print $4}' "$USERS_FILE")" "$(awk -F: -v user="$username" '$1 == user {print $5}' "$USERS_FILE")" "$new_password" "OU=${new_role}s,$OU_PATH"
        assign_role "$username" "$new_role"
        sleep 2
    else
        echo "El usuario '$username' no existe."
        sleep 2
    fi
    show_menu
}

# Función para eliminar un usuario
delete_user() {
    clear
    echo "=== Eliminar Usuario ==="
    read -p "Nombre de usuario a eliminar: " username
    if grep -q "^$username:" "$USERS_FILE" 2>/dev/null; then
        sed -i "/^$username:/d" "$USERS_FILE"
        echo "Usuario '$username' eliminado exitosamente del archivo."

        # Eliminar usuario en Active Directory
        powershell "Remove-ADUser -Identity '$username' -Confirm:\$false"
        sleep 2
    else
        echo "El usuario '$username' no existe."
        sleep 2
    fi
    show_menu
}

# Iniciar el menú
if [ ! -f "$USERS_FILE" ]; then
    touch "$USERS_FILE"
fi

# Crear Unidades Organizacionales (OU)
create_ou "Patologos"
create_ou "Tecnicos"
create_ou "Administrativos"

# Crear grupos para roles
powershell "New-ADGroup -Name 'Grupo_Patologos' -GroupScope Global -Path 'DC=HOSPITALPATOLOGIA,DC=local'"
powershell "New-ADGroup -Name 'Grupo_Tecnicos' -GroupScope Global -Path 'DC=HOSPITALPATOLOGIA,DC=local'"
powershell "New-ADGroup -Name 'Grupo_Administrativos' -GroupScope Global -Path 'DC=HOSPITALPATOLOGIA,DC=local'"

# Configuración inicial de VLANs
configure_vlan() {
    local vlan_id=$1
    local vlan_name=$2
    local switch_ip=$3

    ssh admin@"$switch_ip" <<EOF
    configure terminal
    vlan $vlan_id
    name $vlan_name
    exit
    interface range gigabitethernet 1/0/1-24
    switchport mode access
    switchport access vlan $vlan_id
    exit
    write memory
EOF
}

# Configurar VLANs en switches
configure_vlan 10 "Patologia_Molecular" "192.168.1.10"
configure_vlan 20 "Administracion" "192.168.1.11"

# Mostrar menú inicial
show_menu