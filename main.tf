terraform {
  required_version = ">= 1.1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "cloudinit" {}

resource "azurerm_resource_group" "rg" {
  name     = "${var.labelPrefix}-A05-RG"
  location = var.region
}

resource "azurerm_public_ip" "public_ip" {
  name                = "${var.labelPrefix}-A05-PublicIP"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.region
  allocation_method   = "Dynamic"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.labelPrefix}-A05-VNet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.region
  address_space       = ["10.0.0.0/16"]
}
resource "azurerm_subnet" "subnet" {
  name                 = "${var.labelPrefix}-A05-Subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.labelPrefix}-A05-NSG"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.region

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_network_interface" "nic" {
  name                = "${var.labelPrefix}-A05-NIC"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.region

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    public_ip_address_id          = azurerm_public_ip.public_ip.id
    private_ip_address_allocation = "Dynamic"
  }
}
resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}
data "cloudinit_config" "init" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    content      = file("init.sh")
  }
}
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "${var.labelPrefix}-A05-VM"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.region
  size                = "Standard_B1s"
  admin_username      = var.admin_username
  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("cloud.pub")

  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  custom_data = base64encode(data.cloudinit_config.init.rendered)

}
